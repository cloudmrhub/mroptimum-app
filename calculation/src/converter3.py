import numpy as np
from PIL import Image
import matplotlib.pyplot as plt
from skimage.metrics import mean_squared_error, structural_similarity
import os
import struct

def generate_synthetic_image(n_samples, n_lines):
    """Generate a synthetic image for testing."""
    x, y = np.meshgrid(np.linspace(-1, 1, n_lines), np.linspace(-1, 1, n_samples))  # Shape: (n_samples, n_lines)
    img = np.exp(-(x**2 + y**2) / 0.2)  # Gaussian blob
    return (img * 255).astype(np.uint8)

def generate_kspace_from_image(image_path, n_samples, n_lines, n_channels=1, n_slices=1):
    """
    Generate k-space data from an image for multiple slices.
    
    Parameters:
    - image_path: Path to input image or None for synthetic image.
    - n_samples: Number of samples per readout (width).
    - n_lines: Number of phase-encoding lines (height).
    - n_channels: Number of receiver coils.
    - n_slices: Number of slices.
    
    Returns:
    - complex_data: NumPy array of shape (n_samples, n_channels, n_lines, n_slices).
    - original_img: NumPy array of shape (n_samples, n_lines, n_slices).
    """
    img_stack = np.zeros((n_samples, n_lines, n_slices), dtype=np.float32)
    
    if image_path and os.path.exists(image_path):
        img = Image.open(image_path).convert('L')
        img = img.resize((n_lines, n_samples))  # (width, height) = (n_lines, n_samples)
        img_array_raw = np.array(img)
        print(f"Raw image min: {img_array_raw.min()}, max: {img_array_raw.max()}, shape: {img_array_raw.shape}")
        # Normalize based on bit depth
        max_val = img_array_raw.max()
        if max_val > 255:
            img_array = img_array_raw.astype(np.float32) / max_val  # Normalize to [0, 1]
        else:
            img_array = img_array_raw.astype(np.float32) / 255.0
        print(f"Normalized img_array min: {img_array.min()}, max: {img_array.max()}, shape: {img_array.shape}")
        for s in range(n_slices):
            img_stack[:, :, s] = img_array * (1 - 0.05 * s)
    else:
        for s in range(n_slices):
            img_stack[:, :, s] = generate_synthetic_image(n_samples, n_lines) / 255.0 * (1 - 0.05 * s)
    
    # Debug: Visualize first slice
    plt.imshow(img_stack[:, :, 0], cmap='gray')
    plt.title('Image Slice Before FFT')
    plt.axis('off')
    plt.show()
    
    complex_data = np.zeros((n_samples, n_channels, n_lines, n_slices), dtype=np.complex64)
    
    if n_channels == 1:
        for s in range(n_slices):
            kspace = np.fft.fft2(img_stack[:, :, s])
            kspace = np.fft.fftshift(kspace)
            complex_data[:, 0, :, s] = kspace
    else:
        for ch in range(n_channels):
            x, y = np.meshgrid(np.linspace(-1, 1, n_lines), np.linspace(-1, 1, n_samples))
            sigma = 0.5
            coil_sensitivity = np.exp(-((x - 0.2 * ch)**2 + y**2) / (2 * sigma**2))  # Shape: (n_samples, n_lines)
            for s in range(n_slices):
                coil_image = img_stack[:, :, s] * coil_sensitivity
                kspace = np.fft.fft2(coil_image)
                kspace = np.fft.fftshift(kspace)
                complex_data[:, ch, :, s] = kspace
    
    return complex_data, img_stack

def write_twix_file(filename, complex_data, n_samples, n_channels, n_lines, n_slices):
    """
    Write k-space data to a TWIX-like binary file manually.
    
    Parameters:
    - filename: Output TWIX file path.
    - complex_data: NumPy array of shape (n_samples, n_channels, n_lines, n_slices).
    - n_samples, n_channels, n_lines, n_slices: Data dimensions.
    """
    with open(filename, 'wb') as f:
        # Write header (ASCII, padded to 1024 bytes)
        header = (
            f"TWIX Data\n"
            f"Samples: {n_samples}\n"
            f"Channels: {n_channels}\n"
            f"Lines: {n_lines}\n"
            f"Slices: {n_slices}\n"
            f"DataType: Complex32\n"
        ).encode('utf-8')
        f.write(header)
        f.write(b'\x00' * (1024 - len(header)))
        
        # Write k-space data (interleaved real/imaginary floats)
        for s in range(n_slices):
            for line in range(n_lines):
                for channel in range(n_channels):
                    data_line = complex_data[:, channel, line, s]
                    for sample in data_line:
                        f.write(struct.pack('f', sample.real))
                        f.write(struct.pack('f', sample.imag))

def read_twix_file(filename):
    """
    Read k-space data from a TWIX-like file.
    
    Returns:
    - kspace: NumPy array of shape (n_samples, n_channels, n_lines, n_slices).
    """
    with open(filename, 'rb') as f:
        # Read header (first 1024 bytes)
        header = f.read(1024).decode('utf-8', errors='ignore')
        n_samples, n_channels, n_lines, n_slices = None, None, None, None
        for line in header.split('\n'):
            if line.startswith('Samples:'):
                n_samples = int(line.split(':')[1])
            elif line.startswith('Channels:'):
                n_channels = int(line.split(':')[1])
            elif line.startswith('Lines:'):
                n_lines = int(line.split(':')[1])
            elif line.startswith('Slices:'):
                n_slices = int(line.split(':')[1])
        
        if not all([n_samples, n_channels, n_lines, n_slices]):
            raise ValueError("Could not parse header")
        
        # Read k-space data
        kspace = np.zeros((n_samples, n_channels, n_lines, n_slices), dtype=np.complex64)
        for s in range(n_slices):
            for line in range(n_lines):
                for channel in range(n_channels):
                    for sample in range(n_samples):
                        real = struct.unpack('f', f.read(4))[0]
                        imag = struct.unpack('f', f.read(4))[0]
                        kspace[sample, channel, line, s] = real + 1j * imag
    
    return kspace

def reconstruct_image(kspace):
    """
    Reconstruct image from k-space data for multiple slices.
    
    Parameters:
    - kspace: NumPy array of shape (n_samples, n_channels, n_lines, n_slices).
    
    Returns:
    - recon_img: NumPy array of shape (n_samples, n_lines, n_slices).
    """
    n_samples, n_channels, n_lines, n_slices = kspace.shape
    recon_img = np.zeros((n_samples, n_lines, n_slices), dtype=np.float32)
    
    for s in range(n_slices):
        if n_channels == 1:
            kspace_shifted = np.fft.ifftshift(kspace[:, 0, :, s])
            slice_img = np.fft.ifft2(kspace_shifted)
            recon_img[:, :, s] = np.abs(slice_img)
        else:
            slice_img = np.zeros((n_samples, n_lines), dtype=np.float32)
            for ch in range(n_channels):
                kspace_shifted = np.fft.ifftshift(kspace[:, ch, :, s])
                coil_img = np.fft.ifft2(kspace_shifted)
                slice_img += np.abs(coil_img)**2
            recon_img[:, :, s] = np.sqrt(slice_img)
    
    return recon_img

def compare_images(original, reconstructed):
    """
    Compare original and reconstructed images across slices.
    
    Returns:
    - mse: Mean Squared Error (average over slices).
    - ssim: Structural Similarity Index (average over slices).
    """
    n_slices = original.shape[-1]
    mse_list, ssim_list = [], []
    for s in range(n_slices):
        mse = mean_squared_error(original[:, :, s], reconstructed[:, :, s])
        ssim = structural_similarity(original[:, :, s], reconstructed[:, :, s],
                                     data_range=original[:, :, s].max() - original[:, :, s].min())
        mse_list.append(mse)
        ssim_list.append(ssim)
    return np.mean(mse_list), np.mean(ssim_list)

def main():
    # Parameters
    image_path = 'sample_image.png'  # Set to real image path or None
    n_samples = 512
    n_lines = 256
    n_channels = 4
    n_slices = 3
    twix_file = 'test_output.dat'
    
    # Generate k-space data and original image
    kspace, original_img = generate_kspace_from_image(image_path, n_samples, n_lines, n_channels, n_slices)
    
    # Write to TWIX file
    write_twix_file(twix_file, kspace, n_samples, n_channels, n_lines, n_slices)
    
    # Read back k-space data
    read_kspace = read_twix_file(twix_file)
    
    # Debug: Check k-space fidelity
    print(f"K-space difference max: {np.abs(kspace - read_kspace).max()}")
    
    # Reconstruct image
    recon_img = reconstruct_image(read_kspace)
    
    # Compare images
    mse, ssim = compare_images(original_img, recon_img)
    print(f"Mean Squared Error: {mse:.10f}")
    print(f"SSIM: {ssim:.10f}")
    
    # Visualize results for each slice
    for s in range(n_slices):
        plt.figure(figsize=(10, 5))
        plt.subplot(121)
        plt.imshow(original_img[:, :, s], cmap='gray')
        plt.title(f'Original Image (Slice {s+1})')
        plt.axis('off')
        plt.subplot(122)
        plt.imshow(recon_img[:, :, s], cmap='gray')
        plt.title(f'Reconstructed Image (Slice {s+1})')
        plt.axis('off')
        plt.show()
    
    # Test for exact match
    if mse < 1e-10:
        print("Test Passed: Reconstructed image matches original (MSE < 1e-10).")
    else:
        print("Test Failed: Reconstructed image does not match original.")

if __name__ == '__main__':
    main()