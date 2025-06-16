#!/usr/bin/env python3
import numpy as np
import twixtools
from twixtools import read_twix, write_twix
from skimage.metrics import mean_squared_error, structural_similarity
import matplotlib.pyplot as plt

def make_two_circles(n_lines, n_samples):
    """Create an (n_lines×n_samples) phantom with two filled circles."""
    img = np.zeros((n_lines, n_samples), dtype=np.float32)
    rr, cc = np.ogrid[:n_lines, :n_samples]
    y = rr / n_lines
    x = cc / n_samples
    mask1 = (y - 0.3)**2 + (x - 0.5)**2 < 0.2**2
    mask2 = (y - 0.7)**2 + (x - 0.5)**2 < 0.15**2
    img[mask1] = 1.0
    img[mask2] = 0.7
    return img

def write_twix_from_template(template_dat, out_dat, kspace):
    """
    Overwrite template MDBs in-place with kspace array, then write out.
    kspace: shape (n_slices, n_samples, n_channels, n_lines)
    """
    # load template
    meas = read_twix(template_dat)[-1]
    mdb_list = meas['mdb'] if isinstance(meas, dict) else meas.mdb

    # infer dims from meas_par
    sl = max(m.meas_par['Slc'] for m in mdb_list if m.is_image_scan()) + 1
    ch = max(m.meas_par['Cha'] for m in mdb_list if m.is_image_scan()) + 1
    ln = max(m.meas_par['Lin'] for m in mdb_list if m.is_image_scan()) + 1
    sm = mdb_list[0].data.shape[0]

    # verify
    assert kspace.shape == (sl, sm, ch, ln), \
        f"kspace {kspace.shape} vs template dims ({sl},{sm},{ch},{ln})"

    # reorder to [slice, line, channel, sample]
    arr = np.transpose(kspace, (0, 3, 2, 1))

    # overwrite each block
    idx = 0
    for s in range(sl):
        for l in range(ln):
            for c in range(ch):
                m = mdb_list[idx]
                m._data = arr[s, l, c, :].astype(np.complex64)
                idx += 1

    write_twix(meas, out_dat)
    print(f"Wrote synthetic TWIX to {out_dat}")

def read_and_reconstruct(datfile):
    """Read TWIX, reassemble k-space, do IFFT2 (RSS if multichannel)."""
    meas = read_twix(datfile)[-1]
    mdb_list = meas['mdb'] if isinstance(meas, dict) else meas.mdb

    sl = max(m.meas_par['Slc'] for m in mdb_list if m.is_image_scan()) + 1
    ch = max(m.meas_par['Cha'] for m in mdb_list if m.is_image_scan()) + 1
    ln = max(m.meas_par['Lin'] for m in mdb_list if m.is_image_scan()) + 1
    sm = mdb_list[0].data.shape[0]

    ks = np.zeros((sl, sm, ch, ln), dtype=np.complex64)
    for m in mdb_list:
        if m.is_image_scan():
            ks[m.meas_par['Slc'], :, m.meas_par['Cha'], m.meas_par['Lin']] = m.data

    imgs = np.zeros((sl, sm, ln), dtype=np.float32)
    for s in range(sl):
        if ch == 1:
            tmp = np.fft.ifft2(np.fft.ifftshift(ks[s, :, 0, :]))
            imgs[s] = np.abs(tmp)
        else:
            sos = np.zeros((sm, ln), dtype=np.float32)
            for c in range(ch):
                tmp = np.fft.ifft2(np.fft.ifftshift(ks[s, :, c, :]))
                sos += np.abs(tmp)**2
            imgs[s] = np.sqrt(sos)
    return imgs

def compare_metrics(orig, recon):
    mse  = mean_squared_error(orig, recon)
    ssim = structural_similarity(orig, recon, data_range=orig.max()-orig.min())
    return mse, ssim

def main():
    # template + output paths
    template_dat = '/data/MYDATA/mroptimumtestData/signal.dat'
    out_dat      = '/g/synthetic_twix.dat'

    # load template to infer dims
    meas = read_twix(template_dat)[-1]
    mdbs = meas['mdb'] if isinstance(meas, dict) else meas.mdb
    sl = max(m.meas_par['Slc'] for m in mdbs if m.is_image_scan()) + 1
    ch = max(m.meas_par['Cha'] for m in mdbs if m.is_image_scan()) + 1
    ln = max(m.meas_par['Lin'] for m in mdbs if m.is_image_scan()) + 1
    sm = mdbs[0].data.shape[0]
    print(f"Template dims → slices={sl}, samples={sm}, channels={ch}, lines={ln}")

    # make phantom & k-space
    phantom = make_two_circles(ln, sm)
    ks2d = np.fft.fftshift(np.fft.fft2(phantom))
    kspace = np.zeros((sl, sm, ch, ln), dtype=np.complex64)
    for s in range(sl):
        for c in range(ch):
            kspace[s, :, c, :] = ks2d.T

    # write & read back
    write_twix_from_template(template_dat, out_dat, kspace)
    recon_vol = read_and_reconstruct(out_dat)
    recon_img = recon_vol[0]

    # compare & display
    mse, ssim = compare_metrics(phantom, recon_img)
    print(f"Reconstruction MSE: {mse:.6e}, SSIM: {ssim:.6f}")

    plt.figure(figsize=(8,4))
    plt.subplot(1,2,1); plt.title('Original');    plt.imshow(phantom, cmap='gray'); plt.axis('off')
    plt.subplot(1,2,2); plt.title('Reconstructed'); plt.imshow(recon_img, cmap='gray'); plt.axis('off')
    plt.tight_layout(); plt.show()

if __name__=='__main__':
    main()
