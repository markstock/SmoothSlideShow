/*
 * SmoothSlideShow
 *
 * Randomly and smoothly display all images in a directory, with dwell
 * times varying according to image complexity (file size)
 *
 * (c)2016 Mark J Stock markjstock@gmail.com
 */

// All fades take this long
int fadeMillis = 5000;
// Dwell time min and max (between fades)
int dwellMin = 7000;
int dwellMax = 14000;

long minImgSize = 999999999;
long maxImgSize = 10;
  
// class to contain metadata for each image file
class Image {
  File file;
  String filename;
  long size;
  
  Image(File _name) {
    file = _name;
    filename = file.getAbsolutePath();
    
    // deal with file size
    size = file.length();
    if (size > maxImgSize) {
      maxImgSize = size;
    }
    if (size < minImgSize) {
      minImgSize = size;
    }
  }
}

Image[] img;
int numImg = 0;
int[] imgLeft;
int numImgsLeft = 0;
boolean readyToDraw = false;
boolean mustSetBlends = true;

class DisplayImage {
  PImage image;
  int idx;
  PImage blend;
  int px,py;
  int sx,sy;
  
  DisplayImage() {
    // set placeholders
    idx = 0;
    px = 0;
    py = 0;
    sx = 1;
    sy = 1;
    // init the blendable image dimensions
    image = createImage(width, height, RGB);
    blend = createImage(width, height, RGB);
  }
  
  void copy(DisplayImage from) {
    image = createImage(from.image.width, from.image.height, RGB);
    image.copy(from.image,0,0,from.image.width,from.image.width,
                          0,0,from.image.width,from.image.width);
    idx = from.idx;
    blend.copy(from.blend,0,0,width,height,0,0,width,height);
    px = from.px;
    py = from.py;
    sx = from.sx;
    sy = from.sy;
  }
  
  void setImageIdx(int _idx, int time) {
    idx = _idx;
    println("Requesting " + img[idx].filename + " number "
                          + idx + " at time " + time/1000.0);
    image = requestImage(img[idx].filename);
  }
  
  // use data in image to set corner x,y and on-screen size
  void setOSD() {
    if (image == null) return;
    if (image.width < 1) return;
    // split on aspect ratio
    if (image.width*height > width*image.height) {
      // this scaled image is wider than the screen
      sx = width;
      px = 0;
      sy = (image.height * width) / image.width;
      py = (height - sy)/2;
    } else {
      // aspect ratios match, or this scaled image is narrower than the screen
      sy = height;
      py = 0;
      sx = (image.width * height) / image.height;
      px = (width - sx)/2;
    }
    println("dimensions set to "+px+" "+py+" "+sx+" "+sy);
  }
}

DisplayImage curr, next;
PImage blackImg;

int beginFadeAt = 0;
int endFadeAt = 0;

void setup() {
  // use one of the following two statements
  fullScreen();
  //size(800,600);
  
  frameRate(30);
  background(0);
  noCursor();
  
  // set up an all-black image
  blackImg = createImage(width, height, RGB);
  blackImg.loadPixels();
  for (int i = 0; i < blackImg.pixels.length; i++) {
    blackImg.pixels[i] = color(0);
  }
  blackImg.updatePixels();
  
  // and the pixel data structures
  curr = new DisplayImage();
  next = new DisplayImage();
  curr.image.copy(blackImg, 0,0,width,height, 0,0,width,height);
  curr.setOSD();

  // Select the image folder
  selectFolder("Select a folder with images:", "folderSelected");
}

// pick a random image from the list of unshown images
int pickNewImageIdx() {
  if (numImgsLeft == 0) {
    // reset all flags and pick again
    for (int i=0; i<numImg; i++) {
      //img[i].played = false;
      imgLeft[i] = i;
    }
    numImgsLeft = numImg;
    println("Resetting " + numImgsLeft + " image files");
    return pickNewImageIdx();
  }
  
  // in case of failure, or to show in order, just pick zero
  int thisIdx = 0;
  int thisOne = imgLeft[thisIdx];
  
  // iterate until we get one
  boolean keepGoing = true;
  while (keepGoing) {
    thisIdx = int(random(numImgsLeft));
    thisOne = imgLeft[thisIdx];
    //println("Selected " + thisIdx + " which is image " + thisOne);
    keepGoing = false;
  }
  
  // adjust the imgLeft array (shuffle last index to fill hole)
  imgLeft[thisIdx] = imgLeft[numImgsLeft-1];
  numImgsLeft--;
  
  return thisOne;
}

String getFileExtension(File file) {
  String name = file.getName();
  try {
    return name.substring(name.lastIndexOf(".") + 1);
  } catch (Exception e) {
    return "";
  }
}

void folderSelected(File selection) {
  if (selection == null) {
    println("Window was closed or the user hit cancel.");
  } else {
    println("Using images from " + selection.getAbsolutePath());
    
    // now get the directory listing and load the information
    File[] listOfFiles = selection.listFiles();
    img = new Image[listOfFiles.length];
    imgLeft = new int[listOfFiles.length];
    
    int num = 0;
    for (File file : listOfFiles) {
      if (file.isFile()) {
        println("File " + file.getName() + " has size " + file.length());
        String ext = getFileExtension(file);
        if (ext.equals("png") || ext.equals("jpg")) {
          img[num] = new Image(file);
          imgLeft[num] = num;
          num++;
        }
      }
    }
    
    // Got em all, set up the arrays
    numImg = num;
    numImgsLeft = num;
    if (numImg > 0) {
      println("Found " + numImg + " image files!");
      next.setImageIdx(pickNewImageIdx(), millis());
      readyToDraw = true;
    }
  }
}

void draw() {
  // we explicitly do not call background here - we will always overdraw
  
  // do nothing until the next image should begin fading in
  int timeNow = millis();
  
  // Until we've loaded the image list and metadata, we can't display
  if (!readyToDraw) {
    beginFadeAt = timeNow;
    endFadeAt = beginFadeAt + fadeMillis;
    return;
  }
  
  
  // always in one of 3 modes: waiting for first image, fading, dwelling
  //println("time " + timeNow/1000.0 + " begin " + beginFadeAt/1000.0
  //                + " end " + endFadeAt/1000.0);
  
  
  if (timeNow > beginFadeAt) {
    // blend currImg and newImg
    // this gets run every frame until the blend is done
    
    // if the new image has not loaded, just push back the dwell
    if (next.image == null) {
      // Image is not yet loaded, push back transition
      beginFadeAt = timeNow;
      endFadeAt = beginFadeAt + fadeMillis;
      return;
    }
    if (next.image.width == 0) {
      // Image is not yet loaded, push back transition
      beginFadeAt = timeNow;
      endFadeAt = beginFadeAt + fadeMillis;
      return;
    } else if (next.image.width == -1) {
      // This means an error occurred during image loading
      // try again with another one
      next.setImageIdx(pickNewImageIdx(), timeNow);
      
      // and push back transition
      beginFadeAt = timeNow;
      endFadeAt = beginFadeAt + fadeMillis;
      return;
    }
    
    // If we got here, we have two images that are ready to blend
    
    // Do this chunk only once per transition
    if (mustSetBlends) {
      
      // set the screen coordinates for this image
      next.setOSD();
    
      next.blend.copy(blackImg, 0,0,width,height,
                                0,0,width,height);
      next.blend.copy(next.image, 0,0,next.image.width,next.image.height,
                                  next.px,next.py,next.sx,next.sy);
      
      mustSetBlends = false;
    }
    
    // set the blend factor (b goes from 0 to 1)
    float b = (timeNow - beginFadeAt) / float(endFadeAt - beginFadeAt);
    b = 0.5-0.5*cos(b*3.1415927);
    float oob = 1.0 - b;
    
    // and then blend the two images over it - dammit
    
    // this is a slow way
    /*
    loadPixels();
    curr.blend.loadPixels();
    next.blend.loadPixels();
    for (int i = 0; i < width*height; i++) {
      color cc = curr.blend.pixels[i];
      int cr = (cc >> 16) & 0xFF;
      int cg = (cc >> 8) & 0xFF;
      int cb = cc & 0xFF;
      color nc = next.blend.pixels[i];
      int nr = (nc >> 16) & 0xFF;
      int ng = (nc >> 8) & 0xFF;
      int nb = nc & 0xFF;
      pixels[i] = color((oob*cr+b*nr), (oob*cg+b*ng), (oob*cb+b*nb));
    }
    updatePixels();
    */
    
    // this is faster (but still not fast on a UHD monitor)
    noTint();
    image(curr.blend, 0, 0);
    tint(255,int(256*b));
    image(next.blend, 0, 0);
  }
  
  if (timeNow > endFadeAt) {
    // fade has finished, load next one and dwell on currImg
    // this gets run once per new image
    
    // set up to draw and dwell on currImg
    curr.copy(next);
    
    next.setImageIdx(pickNewImageIdx(), timeNow);
    
    // update fade time for next fade
    float sizeFrac = (img[curr.idx].size - minImgSize)
                   / float(int(maxImgSize - minImgSize));
    int nextDwell = dwellMin + int(sizeFrac*(dwellMax - dwellMin));
    println("Will dwell here for " + nextDwell/1000. + " seconds on "
            + img[curr.idx].size + " bytes");
    beginFadeAt = timeNow + nextDwell;
    endFadeAt = beginFadeAt + fadeMillis;
    mustSetBlends = true;
    
    if (curr.image == null) {
      // should not get here
      println("curr.image is null in draw!");
      exit();
    }
    
    if (curr.image.width > 0) {
      //println("dimensions are "+curr.px+" "+curr.py+" "+curr.sx+" "+curr.sy);
      image(curr.blend, 0, 0, width, height);
    }
  }
  
  // if debug mode is on, write the file name, size, and play time
}

void keyPressed() {
  if (key == 'q') {
    exit();
  }
}