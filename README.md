# xmm_sky2det_regions  
  
Converts DS9 regions files into detector coordinates for use with mos-spectra/pn-spectra
Handles circles, ellipses, boxes (polygons almost implemented)
  
Currently runs from placing inside analysis directory  
Takes two arguments; xxxxxxxx-obj-image-sky-fits, ds9 region file in [DS9/Funtools, CIAO, SAOtng] formats  
Third optional argument is output file name (expected without file extension!)  
Output are two region files in detector coordinates  
  -outfile.reg (DS9 formatted)  
  -outfile.txt (XMM formatted)  
  
# Pre-reqs  
bc - Basic Calculator 1.07.1  
wcstools 3.9.5  
  
Make sure to have SAS paths set appropriately  
SAS_CCFPATH, SAS_CCF and SAS_ODF  
  
# Example  
  
ds9.reg contains the region:  
 box(9:56:35.9111,+69:36:53.095,656.723",85.926",320.71996) # color=white width=4  
  
[USER analysis]$ ./sky2det.sh mos1S001-obj-image-sky.fits ds9.reg  
  
Output detector regions in files  
 outfile.reg:  
  box(596.9,-6683.9,13134.4599958949,1718.5199975862,358.561930869141) # color=white width=4  
 outfile.txt:  
  &&((DETX,DETY) IN box(596.9,-6683.9,13134.4599958949,1718.5199975862,358.561930869141))  
