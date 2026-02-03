#!/usr/bin/env python3
import numpy as np
import twixtools
from twixtools import map_twix, write_twix, read_twix
from skimage.metrics import mean_squared_error, structural_similarity
import matplotlib.pyplot as plt
import warnings

# --- PHANTOM AND COMPARISON HELPERS (Unchanged) ---

def make_two_circles(height, width):
    """Generate a height x width image with two filled circles."""
    img = np.zeros((height, width), dtype=np.float32)
    rr, cc = np.ogrid[:height, :width]
    # Scale coordinates to be resolution-independent
    y_norm, x_norm = rr / height, cc / width
    mask1 = (y_norm - 0.3)**2 + (x_norm - 0.5)**2 < (0.2)**2
    mask2 = (y_norm - 0.7)**2 + (x_norm - 0.5)**2 < (0.15)**2
    img[mask1] = 1.0
    img[mask2] = 0.7
    return img

def compare_imgs(orig, recon):
    """Compute MSE and SSIM between two 2D images."""
    # Normalize recon to match the scale of orig for fair comparison
    recon_scaled = recon * (orig.max() / recon.max())
    mse = mean_squared_error(orig, recon_scaled)
    ssim = structural_similarity(orig, recon_scaled,
                                 data_range=orig.max() - orig.min())
    return mse, ssim


# --- ROBUST TWIX I/O FUNCTIONS ---

def _find_dim_index(dims_tuple, possible_names):
    """
    Finds the index of a dimension from a list of possible names.

    Args:
        dims_tuple (tuple): The tuple of dimension names from the twix_array.
        possible_names (list): A list of possible names for the dimension (e.g., ['Slc', 'Sli']).

    Returns:
        int: The index of the found dimension.

    Raises:
        RuntimeError: If none of the possible names are found in the tuple.
    """
    for name in possible_names:
        if name in dims_tuple:
            return dims_tuple.index(name)
    raise RuntimeError(f"Could not find any of the dimension names {possible_names} in template dims {dims_tuple}")

def write_twix_from_template(template_dat, out_dat, kspace_4d):
    """
    Writes a 4D k-space array into a Siemens .dat file using a template.

    This function intelligently maps the input k-space to the template's
    complex dimensional structure, handling extra dimensions like repetitions
    or echoes by tiling the input data.

    Args:
        template_dat (str): Path to the template Siemens .dat file.
        out_dat (str): Path for the output synthetic .dat file.
        kspace_4d (np.ndarray): Input k-space with shape:
                      (frequency_encoding, phase_encoding, n_channels, n_slices)
    """
    print(f"Reading template file: {template_dat}")
    # 1. Read the template file to get header information and measurement objects.
    meas = read_twix(template_dat)[-1]
    twix_map = map_twix(meas)
    img_tarr = twix_map['image']

    print(f"Template k-space dimensions: {img_tarr.dims}")
    print(f"Template k-space shape: {img_tarr.shape}")

    # 2. Extract the shape of the user's input k-space.
    n_freq, n_phase, n_ch, n_sl = kspace_4d.shape
    print(f"Input k-space shape (Freq, Phase, Chan, Slice): ({n_freq}, {n_phase}, {n_ch}, {n_sl})")

    # 3. Identify the axis index for the core dimensions in the template file.
    #    This is now flexible to handle common variations like 'Slc' vs 'Sli'.
    try:
        col_idx = _find_dim_index(img_tarr.dims, ['Col'])
        lin_idx = _find_dim_index(img_tarr.dims, ['Lin'])
        cha_idx = _find_dim_index(img_tarr.dims, ['Cha'])
        slc_idx = _find_dim_index(img_tarr.dims, ['Slc', 'Sli']) # Accept 'Slc' or 'Sli'
    except RuntimeError as e:
        raise RuntimeError(f"Template dimension discovery failed: {e}") from e


    # 4. Check if the core dimensions of the input match the template.
    if img_tarr.shape[col_idx] != n_freq:
        raise ValueError(f"Frequency encoding mismatch: Template needs {img_tarr.shape[col_idx]}, you provided {n_freq}")
    if img_tarr.shape[lin_idx] != n_phase:
        raise ValueError(f"Phase encoding mismatch: Template needs {img_tarr.shape[lin_idx]}, you provided {n_phase}")
    if img_tarr.shape[cha_idx] != n_ch:
        raise ValueError(f"Channel count mismatch: Template needs {img_tarr.shape[cha_idx]}, you provided {n_ch}")
    if img_tarr.shape[slc_idx] != n_sl:
        raise ValueError(f"Slice count mismatch: Template needs {img_tarr.shape[slc_idx]}, you provided {n_sl}")

    # 5. Prepare the input data for injection into the template's structure.
    # Let's create a 4D array ordered by (Slice, Chan, Phase, Freq)
    kspace_ordered = np.transpose(kspace_4d, (3, 2, 1, 0)) # Now shape (n_sl, n_ch, n_phase, n_freq)

    # Now, let's create the full N-dimensional array for the template
    full_kspace = np.zeros(img_tarr.shape, dtype=np.complex64)
    
    # Create an iterator for all non-spatial dimensions (e.g., Reps, Ecos)
    from itertools import product
    slice_dim_name = img_tarr.dims[slc_idx] # Get the actual slice dimension name used
    core_dims = ['Col', 'Lin', 'Cha', slice_dim_name]
    loop_dims_indices = [i for i, dim in enumerate(img_tarr.dims) if dim not in core_dims]
    loop_dims_shape = [img_tarr.shape[i] for i in loop_dims_indices]
    
    if not loop_dims_indices: # Simple case: only 4 dimensions
        # We still need to reshape to the target shape to ensure dimension order is correct
        # This is tricky because the order isn't guaranteed.
        # A safer way is to permute our 4D array to match the template's 4D structure.
        target_permute = [slc_idx, cha_idx, lin_idx, col_idx]
        inv_permute = np.argsort(target_permute)
        full_kspace = np.transpose(kspace_ordered, inv_permute)
    else:
        # compute the transpose that maps your (slc,cha,lin,col) kspace_ordered
        # into the template’s (slc,lin,cha,col) slice-order
        target_permute = [slc_idx, cha_idx, lin_idx, col_idx]
        inv_permute    = np.argsort(target_permute)
        # permuted_kspace now has shape (5,96,16,192) to match full_kspace[tuple(idx)]
        permuted_kspace = np.transpose(kspace_ordered, inv_permute)

        print(f"Tiling data across extra dimensions: {[img_tarr.dims[i] for i in loop_dims_indices]}")
        for loop_pos in product(*(range(s) for s in loop_dims_shape)):
            idx = [slice(None)] * len(img_tarr.shape)
            for i, pos in enumerate(loop_pos):
                idx[loop_dims_indices[i]] = pos

            full_kspace[tuple(idx)] = permuted_kspace



    # 7. Swap our full_kspace into the 'image' entry of the twix_map
    twix_map = map_twix(meas)
    twix_map['image'] = full_kspace

    # 8. Write the modified measurement object back to a new file.
    write_twix(meas, out_dat, twix_map)
    print(f"Wrote synthetic TWIX file to {out_dat}")


def read_and_reconstruct(datfile):
    """
    Reads k-space from a .dat file and performs a simple 2D IFFT-RSS reconstruction.
    This version is robust to different dimension orders.
    """
    print(f"\nReading and reconstructing: {datfile}")
    meas = read_twix(datfile)[-1]
    twix_map = map_twix(meas)
    # debug: what keys are available?
    print(f"map_twix keys: {list(twix_map.keys())}")
    # pick the real k-space container (not whatever 'image' is now)
    for candidate in ('image', 'raw', 'kspace', 'k-space'):
        if candidate in twix_map:
            arr = twix_map[candidate]
            break
    else:
        raise RuntimeError(f"No k-space array in map; found keys {list(twix_map.keys())}")

    # extract a real ndarray
    if hasattr(arr, 'values'):
        img_data = arr.values
    else:
        img_data = np.array(arr)

    # and keep dims for indexing
    dims = arr.dims if hasattr(arr, 'dims') else img_tarr.dims

    # Find the necessary dimensions flexibly
    try:
        col_idx = _find_dim_index(dims, ['Col'])
        lin_idx = _find_dim_index(dims, ['Lin'])
        cha_idx = _find_dim_index(dims, ['Cha'])
        slc_idx = _find_dim_index(dims, ['Slc', 'Sli']) # Accept 'Slc' or 'Sli'
    except RuntimeError as e:
        raise RuntimeError(f"Reconstruction failed. Dimension discovery failed: {e}")

    # — Collapse any extra dimensions (e.g. Reps, Eco) by taking index 0 —
    # build an index for each dim: slice(None) for core, 0 for others
    core_names = ['Slc','Sli','Cha','Lin','Col']
    idx = [ slice(None) if d in core_names else 0
            for d in dims ]
    data4d = img_data[tuple(idx)]

    # — Permute that 4D to (slice, channel, line, column) —
    reduced_dims = [d for d in dims if d in core_names]
    # find their order in data4d
    sl_i = reduced_dims.index('Slc') if 'Slc' in reduced_dims else reduced_dims.index('Sli')
    ch_i = reduced_dims.index('Cha')
    li_i = reduced_dims.index('Lin')
    co_i = reduced_dims.index('Col')
    first_volume_kspace = np.transpose(data4d, (sl_i, ch_i, li_i, co_i))

    sl, ch, li, co = first_volume_kspace.shape
    print(f"Reconstructing volume with shape (Slc, Cha, Lin, Col): ({sl}, {ch}, {li}, {co})")
    
    imgs = np.zeros((sl, li, co), dtype=np.float32)
    for s in range(sl):
        k_slice = first_volume_kspace[s, :, :, :]
        img_ch = np.fft.ifft2(np.fft.ifftshift(k_slice, axes=(-2, -1)), axes=(-2, -1))
        # Root-Sum-of-Squares (RSS) combination
        imgs[s] = np.sqrt(np.sum(np.abs(img_ch)**2, axis=0))
        
    return imgs


def main():
    # --- STEP 1: DEFINE THE SYNTHETIC K-SPACE ---
    # Define the parameters for our desired output image.
    N_freq_enc = 192
    N_phase_enc = 96
    N_channels = 16
    N_slices = 1 # NOTE: Your template file has 5 slices. This must be 5 to match.
    
    # Let's dynamically check the template instead of hardcoding.
    # For this main function, we'll stick to a fixed size that matches the example data.
    template_slices = 5
    N_slices = template_slices # Set this to match the template for this example to work.


    # Create a 2D image phantom.
    # phantom shape will be (N_phase_enc, N_freq_enc) -> (96, 192)
    phantom = make_two_circles(N_phase_enc, N_freq_enc)

    # Convert the phantom to k-space via 2D FFT.
    # kspace_2d shape is also (N_phase_enc, N_freq_enc) -> (96, 192)
    kspace_2d = np.fft.fftshift(np.fft.fft2(phantom))

    # Create the final 4D k-space array in the desired format:
    # (frequency_encoding, phase_encoding, n_channels, n_slices)
    # kspace_4d shape will be (192, 96, 16, 5)
    kspace_4d = np.zeros((N_freq_enc, N_phase_enc, N_channels, N_slices), dtype=np.complex64)
    for sl in range(N_slices):
        # Make each slice phantom slightly different
        slice_phantom = make_two_circles(N_phase_enc, N_freq_enc) * (1 - sl * 0.1)
        slice_kspace_2d = np.fft.fftshift(np.fft.fft2(slice_phantom))
        for ch in range(N_channels):
            # We must transpose kspace_2d from (phase, freq) to (freq, phase) to match the slice shape.
            kspace_4d[:, :, ch, sl] = slice_kspace_2d.T * (1 + (ch - N_channels/2) * 0.01j)

    # --- STEP 2: DEFINE FILE PATHS ---
    # IMPORTANT: Use a template file that has dimensions GREATER THAN OR EQUAL TO
    # the synthetic data you are creating.
    template_dat = '/data/MYDATA/mroptimumtestData/signal.dat'
    out_dat      = '/g/synthetic_twix_v4.dat'

    # --- STEP 3: WRITE THE SYNTHETIC TWIX FILE ---
    try:
        write_twix_from_template(template_dat, out_dat, kspace_4d)

        # --- STEP 4: READ BACK AND RECONSTRUCT FOR VERIFICATION ---
        recon_imgs = read_and_reconstruct(out_dat)
        reconstructed_slice = recon_imgs[0] # Visualize the first reconstructed slice

        # --- STEP 5: COMPARE AND VISUALIZE ---
        # We compare with the phantom for the first slice
        first_slice_phantom = make_two_circles(N_phase_enc, N_freq_enc) * (1 - 0 * 0.1)
        mse, ssim = compare_imgs(first_slice_phantom, reconstructed_slice)
        print(f"\nReconstruction Metrics (Slice 0) -> MSE: {mse:.6e}, SSIM: {ssim:.6f}")

        plt.figure(figsize=(12, 5))
        plt.subplot(1, 3, 1)
        plt.title('Original Phantom (Slice 0)')
        plt.imshow(first_slice_phantom, cmap='gray')
        plt.axis('off')
        
        plt.subplot(1, 3, 2)
        plt.title(f'K-Space (Log Mag, Slice 0)')
        plt.imshow(np.log(np.abs(np.fft.fftshift(np.fft.fft2(first_slice_phantom))) + 1e-9), cmap='gray')
        plt.axis('off')

        plt.subplot(1, 3, 3)
        plt.title('Reconstructed Image (Slice 0)')
        plt.imshow(reconstructed_slice, cmap='gray')
        plt.axis('off')
        
        plt.suptitle("TWIX Synthesis and Reconstruction Pipeline", fontsize=16)
        plt.tight_layout(rect=[0, 0, 1, 0.96])
        plt.show()

    except (ValueError, RuntimeError, FileNotFoundError) as e:
        print(f"\n--- AN ERROR OCCURRED ---")
        print(f"Error: {e}")
        print("Please check that the template file exists and that its dimensions\n"
              "(resolution, channels, slices) are compatible with your input data.")


if __name__ == '__main__':
    # Suppress warnings from twixtools about protocol inconsistencies, as they are expected.
    warnings.filterwarnings('ignore', category=UserWarning, module='twixtools')
    main()
