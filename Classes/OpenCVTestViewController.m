#import "OpenCVTestViewController.h"

#import <opencv/cv.h>

@implementation OpenCVTestViewController
@synthesize imageView;

- (void)dealloc {
	AudioServicesDisposeSystemSoundID(alertSoundID);
	[timeRecorder release];
	[imageView dealloc];
	[super dealloc];
}

#pragma mark -
#pragma mark OpenCV Support Methods

// NOTE you SHOULD cvReleaseImage() for the return value when end of the code.
- (IplImage *)CreateIplImageFromUIImage:(UIImage *)image {
	CGImageRef imageRef = image.CGImage;

	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	IplImage *iplimage = cvCreateImage(cvSize(image.size.width, image.size.height), IPL_DEPTH_8U, 4);
	CGContextRef contextRef = CGBitmapContextCreate(iplimage->imageData, iplimage->width, iplimage->height,
													iplimage->depth, iplimage->widthStep,
													colorSpace, kCGImageAlphaPremultipliedLast|kCGBitmapByteOrderDefault);
	CGContextDrawImage(contextRef, CGRectMake(0, 0, image.size.width, image.size.height), imageRef);
	CGContextRelease(contextRef);
	CGColorSpaceRelease(colorSpace);

	IplImage *ret = cvCreateImage(cvGetSize(iplimage), IPL_DEPTH_8U, 3);
	cvCvtColor(iplimage, ret, CV_RGBA2BGR);
	cvReleaseImage(&iplimage);

	return ret;
}

// NOTE You should convert color mode as RGB before passing to this function
- (UIImage *)UIImageFromIplImage:(IplImage *)image {
	//NSLog(@"IplImage (%d, %d) %d bits by %d channels, %d bytes/row %s", image->width, image->height, image->depth, image->nChannels, image->widthStep, image->channelSeq);

	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	NSData *data = [NSData dataWithBytes:image->imageData length:image->imageSize];
	CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
	CGImageRef imageRef = CGImageCreate(image->width, image->height,
										image->depth, image->depth * image->nChannels, image->widthStep,
										colorSpace, kCGImageAlphaNone|kCGBitmapByteOrderDefault,
										provider, NULL, false, kCGRenderingIntentDefault);
	UIImage *ret = [UIImage imageWithCGImage:imageRef];
	CGImageRelease(imageRef);
	CGDataProviderRelease(provider);
	CGColorSpaceRelease(colorSpace);
	return ret;
}

#pragma mark -
#pragma mark Utilities for intarnal use

- (void)showProgressIndicator:(NSString *)text {
	//[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
	self.view.userInteractionEnabled = FALSE;
	if(!progressHUD) {
		CGFloat w = 160.0f, h = 120.0f;
		progressHUD = [[UIProgressHUD alloc] initWithFrame:CGRectMake((self.view.frame.size.width-w)/2, (self.view.frame.size.height-h)/2, w, h)];
		[progressHUD setText:text];
		[progressHUD showInView:self.view];
	}
}

- (void)hideProgressIndicator {
	//[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
	self.view.userInteractionEnabled = TRUE;
	if(progressHUD) {
		[progressHUD hide];
		[progressHUD release];
		progressHUD = nil;

		AudioServicesPlaySystemSound(alertSoundID);
	}
}

- (void)opencvEdgeDetect {
	if(imageView.image) {
		cvSetErrMode(CV_ErrModeParent);

		// Create grayscale IplImage from UIImage
		IplImage *img_color = [self CreateIplImageFromUIImage:imageView.image];
		IplImage *img = cvCreateImage(cvGetSize(img_color), IPL_DEPTH_8U, 1);
		cvCvtColor(img_color, img, CV_BGR2GRAY);
		cvReleaseImage(&img_color);
		
		// Detect edge
		IplImage *img2 = cvCreateImage(cvGetSize(img), IPL_DEPTH_8U, 1);
		cvCanny(img, img2, 64, 128, 3);
		cvReleaseImage(&img);
		
		// Convert black and whilte to 24bit image then convert to UIImage to show
		IplImage *image = cvCreateImage(cvGetSize(img2), IPL_DEPTH_8U, 3);
		for(int y=0; y<img2->height; y++) {
			for(int x=0; x<img2->width; x++) {
				char *p = image->imageData + y * image->widthStep + x * 3;
				*p = *(p+1) = *(p+2) = img2->imageData[y * img2->widthStep + x];
			}
		}
		cvReleaseImage(&img2);
		imageView.image = [self UIImageFromIplImage:image];
		cvReleaseImage(&image);

		[self hideProgressIndicator];
	}
}

- (void) opencvFaceDetect:(UIImage *)overlayImage  {
	if(imageView.image) {
		cvSetErrMode(CV_ErrModeParent);

		IplImage *image = [self CreateIplImageFromUIImage:imageView.image];
		
		// Scaling down
		IplImage *small_image = cvCreateImage(cvSize(image->width/2,image->height/2), IPL_DEPTH_8U, 3);
		cvPyrDown(image, small_image, CV_GAUSSIAN_5x5);
		int scale = 2;
		
		// Load XML
		NSString *path = [[NSBundle mainBundle] pathForResource:@"haarcascade_frontalface_default" ofType:@"xml"];
		CvHaarClassifierCascade* cascade = (CvHaarClassifierCascade*)cvLoad([path cStringUsingEncoding:NSASCIIStringEncoding], NULL, NULL, NULL);
		CvMemStorage* storage = cvCreateMemStorage(0);
		
		// Detect faces and draw rectangle on them
		CvSeq* faces = cvHaarDetectObjects(small_image, cascade, storage, 1.2f, 2, CV_HAAR_DO_CANNY_PRUNING, cvSize(20, 20));
		cvReleaseImage(&small_image);
		
		// Create canvas to show the results
		CGImageRef imageRef = imageView.image.CGImage;
		CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
		CGContextRef contextRef = CGBitmapContextCreate(NULL, imageView.image.size.width, imageView.image.size.height,
														8, imageView.image.size.width * 4,
														colorSpace, kCGImageAlphaPremultipliedLast|kCGBitmapByteOrderDefault);
		CGContextDrawImage(contextRef, CGRectMake(0, 0, imageView.image.size.width, imageView.image.size.height), imageRef);
		
		CGContextSetLineWidth(contextRef, 4);
		CGContextSetRGBStrokeColor(contextRef, 0.0, 0.0, 1.0, 0.5);
		
		// Draw results on the iamge
		for(int i = 0; i < faces->total; i++) {
			NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
			
			// Calc the rect of faces
			CvRect cvrect = *(CvRect*)cvGetSeqElem(faces, i);
			CGRect face_rect = CGContextConvertRectToDeviceSpace(contextRef, CGRectMake(cvrect.x * scale, cvrect.y * scale, cvrect.width * scale, cvrect.height * scale));
			
			if(overlayImage) {
				CGContextDrawImage(contextRef, face_rect, overlayImage.CGImage);
			} else {
				CGContextStrokeRect(contextRef, face_rect);
			}
			
			[pool release];
		}
		
		imageView.image = [UIImage imageWithCGImage:CGBitmapContextCreateImage(contextRef)];
		CGContextRelease(contextRef);
		CGColorSpaceRelease(colorSpace);
		
		cvReleaseMemStorage(&storage);
		cvReleaseHaarClassifierCascade(&cascade);

		[self hideProgressIndicator];
	}
}

//#define STEP1
//#define STEP2
//#define STEP3
//#define STEP4
//#define STEP5
//#define STEP6
//#define STEP7
//#define STEP8
#define STEP9

void mosaic(char *imgImageData, char *dstImageData, int width, int sX, int sY, int w, int h, int wmSize, int hmSize, int stride) {
	int dp = width * 3 * hmSize;
	int dpp = wmSize * 3;
	unsigned int r, g, b;
	int p, pp, c;
	c = wmSize * hmSize;
	
	for (int y = sY; y < h; y++) {
		p = y * dp + sX;
		for (int x = sX; x < w; x++, p += dpp) {
			r = b = g = 0;
			pp = p;
			for (int yy = 0; yy < hmSize; yy++) {
				for (int xx = 0; xx < wmSize; xx++) {
					b += (unsigned char)imgImageData[pp++];
					g += (unsigned char)imgImageData[pp++];
					r += (unsigned char)imgImageData[pp++];
				}
				pp += stride;
			}
			r /= c;
			g /= c;
			b /= c;
			
			pp = p;
			for (int yy = 0; yy < hmSize; yy++) {
				for (int xx = 0; xx < wmSize; xx++) {
					dstImageData[pp++] = (char)r;
					dstImageData[pp++] = (char)g;
					dstImageData[pp++] = (char)b;
				}
				pp += stride;
			}
		}
	}
}

void mosaic2(char *imgImageData, char *dstImageData, int width, int height, int wmSize, int hmSize) {
	unsigned int elmCnt = (unsigned int) ( width / wmSize) + 1;
	unsigned int r[elmCnt];
	unsigned int g[elmCnt];
	unsigned int b[elmCnt];
	unsigned int square[elmCnt];
	unsigned int mappingTable[width * 3]; // 変換テーブル
	int stride = width * 3;
	int wmSize3 = wmSize * 3;
	for ( int i = 0; i < stride; i++) {
		mappingTable[i] = (unsigned int) ( i / wmSize3);
	}
	
	int p = 0, pp;
	int nextLine = width * 3 * hmSize;
	int length = width * height * 3;
	
	for ( int lineStart = 0; lineStart < length; lineStart += nextLine) {
		for ( unsigned int i = 0; i < elmCnt; i++) {
			r[i] = g[i] = b[i] = square[i] = 0;
		}
		int lineEnd = ( lineStart + nextLine) > length ? length: ( lineStart + nextLine);
		for ( p = lineStart; p < lineEnd;) {
			pp = mappingTable[p % stride];
			b[pp] += (unsigned char)imgImageData[p++];
			g[pp] += (unsigned char)imgImageData[p++];
			r[pp] += (unsigned char)imgImageData[p++];
			square[pp]++;
		}
		
		for ( unsigned int i = 0; i < elmCnt && square[i] > 0; i++) {
			r[i] /= square[i];
			g[i] /= square[i];
			b[i] /= square[i];
		}
		
		for ( p = lineStart; p < lineEnd;) {
			pp = mappingTable[p % stride];
			dstImageData[p++] = (char) r[pp];
			dstImageData[p++] = (char) g[pp];
			dstImageData[p++] = (char) b[pp];
		}
	}
}

- (void)opencvMosaic:(NSNumber*)mosaicSize {
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	if (imageView.image) {
		[timeRecorder start];
#if defined(STEP1)
		int mSize = [mosaicSize intValue];
		IplImage *img = [self CreateIplImageFromUIImage:imageView.image];
		IplImage *dst = cvCreateImage(cvGetSize(img), img->depth, img->nChannels);
		unsigned int r, g, b;
		int p, pp, c;
		
		for (int i = 0; i < img->height; i += mSize) {
			for (int j = 0; j < img->width; j += mSize) {
				r = b = g = 0;
				p = (i * img->width + j) * 3;
				c = 0;
				for (int k = 0; k < mSize; k++) {
					if (i + k < img->height) {
						for (int l = 0; l < mSize; l++) {
							if (j + l < img->width) {
								pp = p + (k * img->width + l) * 3;
								b += (unsigned char)img->imageData[pp];
								g += (unsigned char)img->imageData[pp + 1];
								r += (unsigned char)img->imageData[pp + 2];
								c++;
							}
						}
					}
				}
				r /= c;
				g /= c;
				b /= c;
				
				for (int k = 0; k < mSize; k++) {
					if (i + k < img->height) {
						for (int l = 0; l < mSize; l++) {
							if (j + l < img->width) {
								pp = p + (k * img->width + l) * 3;
								dst->imageData[pp] = (char)r;
								dst->imageData[pp + 1] = (char)g;
								dst->imageData[pp + 2] = (char)b;
							}
						}
					}
				}
			}
		}
		cvReleaseImage(&img);
		imageView.image = [self UIImageFromIplImage:dst];
		cvReleaseImage(&dst);
#elif defined(STEP2)
		int mSize = [mosaicSize intValue];
		IplImage *img = [self CreateIplImageFromUIImage:imageView.image];
		IplImage *dst = cvCreateImage(cvGetSize(img), img->depth, img->nChannels);
		unsigned int r, g, b;
		int p, pp, c;
		int width = img->width;
		int height = img->height;
		
		for (int i = 0; i < height; i += mSize) {
			for (int j = 0; j < width; j += mSize) {
				r = b = g = 0;
				p = (i * width + j) * 3;
				c = 0;
				for (int k = 0; k < mSize; k++) {
					if (i + k < height) {
						for (int l = 0; l < mSize; l++) {
							if (j + l < width) {
								pp = p + (k * width + l) * 3;
								b += (unsigned char)img->imageData[pp];
								g += (unsigned char)img->imageData[pp + 1];
								r += (unsigned char)img->imageData[pp + 2];
								c++;
							}
						}
					}
				}
				r /= c;
				g /= c;
				b /= c;
				
				for (int k = 0; k < mSize; k++) {
					if (i + k < height) {
						for (int l = 0; l < mSize; l++) {
							if (j + l < width) {
								pp = p + (k * width + l) * 3;
								dst->imageData[pp] = (char)r;
								dst->imageData[pp + 1] = (char)g;
								dst->imageData[pp + 2] = (char)b;
							}
						}
					}
				}
			}
		}
		cvReleaseImage(&img);
		imageView.image = [self UIImageFromIplImage:dst];
		cvReleaseImage(&dst);
#elif defined(STEP3)
		int mSize = [mosaicSize intValue];
		IplImage *img = [self CreateIplImageFromUIImage:imageView.image];
		IplImage *dst = cvCreateImage(cvGetSize(img), img->depth, img->nChannels);
		unsigned int r, g, b;
		int p, pp, c;
		int width = img->width;
		int height = img->height;
		int kMax, lMax;
		for (int i = 0; i < height; i += mSize) {
			for (int j = 0; j < width; j += mSize) {
				r = b = g = 0;
				p = (i * width + j) * 3;
				c = 0;
				kMax = i + mSize < height ? mSize : height - i;
				lMax = j + mSize < width  ? mSize : width - j;
				for (int k = 0; k < kMax; k++) {
					for (int l = 0; l < lMax; l++) {
						pp = p + (k * width + l) * 3;
						b += (unsigned char)img->imageData[pp];
						g += (unsigned char)img->imageData[pp + 1];
						r += (unsigned char)img->imageData[pp + 2];
						c++;
					}
				}
				r /= c;
				g /= c;
				b /= c;
				
				for (int k = 0; k < kMax; k++) {
					for (int l = 0; l < lMax; l++) {
						pp = p + (k * width + l) * 3;
						dst->imageData[pp] = (char)r;
						dst->imageData[pp + 1] = (char)g;
						dst->imageData[pp + 2] = (char)b;
					}
				}
			}
		}
		cvReleaseImage(&img);
		imageView.image = [self UIImageFromIplImage:dst];
		cvReleaseImage(&dst);
#elif defined(STEP4)
		int mSize = [mosaicSize intValue];
		IplImage *img = [self CreateIplImageFromUIImage:imageView.image];
		IplImage *dst = cvCreateImage(cvGetSize(img), img->depth, img->nChannels);
		unsigned int r, g, b;
		int p, pp, c;
		int width = img->width;
		int height = img->height;
		int kMax, lMax;
		char *imgImageData = img->imageData;
		char *dstImageData = dst->imageData;
		for (int i = 0; i < height; i += mSize) {
			for (int j = 0; j < width; j += mSize) {
				r = b = g = 0;
				p = (i * width + j) * 3;
				kMax = i + mSize < height ? mSize : height - i;
				lMax = j + mSize < width  ? mSize : width - j;
				c = kMax * lMax;
				for (int k = 0; k < kMax; k++) {
					for (int l = 0; l < lMax; l++) {
						pp = p + (k * width + l) * 3;
						b += (unsigned char)imgImageData[pp];
						g += (unsigned char)imgImageData[pp + 1];
						r += (unsigned char)imgImageData[pp + 2];
					}
				}
				r /= c;
				g /= c;
				b /= c;
				
				for (int k = 0; k < kMax; k++) {
					for (int l = 0; l < lMax; l++) {
						pp = p + (k * width + l) * 3;
						dstImageData[pp] = (char)r;
						dstImageData[pp + 1] = (char)g;
						dstImageData[pp + 2] = (char)b;
					}
				}
			}
		}
		cvReleaseImage(&img);
		imageView.image = [self UIImageFromIplImage:dst];
		cvReleaseImage(&dst);
#elif defined(STEP5)
		int mSize = [mosaicSize intValue];
		IplImage *img = [self CreateIplImageFromUIImage:imageView.image];
		IplImage *dst = cvCreateImage(cvGetSize(img), img->depth, img->nChannels);
		unsigned int r, g, b;
		int p, pp, c;
		int width = img->width;
		int height = img->height;
		int kMax, lMax;
		char *imgImageData = img->imageData;
		char *dstImageData = dst->imageData;
		for (int i = 0; i < height; i += mSize) {
			for (int j = 0; j < width; j += mSize) {
				r = b = g = 0;
				p = (i * width + j) * 3;
				kMax = i + mSize < height ? mSize : height - i;
				lMax = j + mSize < width  ? mSize : width - j;
				c = kMax * lMax;
				for (int k = 0; k < kMax; k++) {
					pp = p + (k * width * 3);
					for (int l = 0; l < lMax; l++) {
						b += (unsigned char)imgImageData[pp++];
						g += (unsigned char)imgImageData[pp++];
						r += (unsigned char)imgImageData[pp++];
					}
				}
				r /= c;
				g /= c;
				b /= c;
				
				for (int k = 0; k < kMax; k++) {
					pp = p + (k * width * 3);
					for (int l = 0; l < lMax; l++) {
						dstImageData[pp++] = (char)r;
						dstImageData[pp++] = (char)g;
						dstImageData[pp++] = (char)b;
					}
				}
			}
		}
		cvReleaseImage(&img);
		imageView.image = [self UIImageFromIplImage:dst];
		cvReleaseImage(&dst);
#elif defined(STEP6)
		int mSize = [mosaicSize intValue];
		IplImage *img = [self CreateIplImageFromUIImage:imageView.image];
		IplImage *dst = cvCreateImage(cvGetSize(img), img->depth, img->nChannels);
		unsigned int r, g, b;
		int p, pp, c;
		int width = img->width;
		int height = img->height;
		int stride = width * 3;
		int offset;
		int kMax, lMax;
		char *imgImageData = img->imageData;
		char *dstImageData = dst->imageData;
		for (int i = 0; i < height; i += mSize) {
			for (int j = 0; j < width; j += mSize) {
				r = b = g = 0;
				p = (i * width + j) * 3;
				kMax = i + mSize < height ? mSize : height - i;
				lMax = j + mSize < width  ? mSize : width - j;
				c = kMax * lMax;
				pp = offset = p;
				for (int k = 0; k < kMax; k++) {	
					for (int l = 0; l < lMax; l++) {
						b += (unsigned char)imgImageData[pp++];
						g += (unsigned char)imgImageData[pp++];
						r += (unsigned char)imgImageData[pp++];
					}
					offset += stride;
					pp = offset;
				}
				r /= c;
				g /= c;
				b /= c;
				pp = offset = p;
				for (int k = 0; k < kMax; k++) {
					for (int l = 0; l < lMax; l++) {
						dstImageData[pp++] = (char)r;
						dstImageData[pp++] = (char)g;
						dstImageData[pp++] = (char)b;
					}
					offset += stride;
					pp = offset;
				}
			}
		}
		cvReleaseImage(&img);
		imageView.image = [self UIImageFromIplImage:dst];
		cvReleaseImage(&dst);
#elif defined(STEP7)
		int mSize = [mosaicSize intValue];
		IplImage *img = [self CreateIplImageFromUIImage:imageView.image];
		IplImage *dst = cvCreateImage(cvGetSize(img), img->depth, img->nChannels);
		unsigned int r, g, b;
		int p, pp, c;
		int width = img->width;
		int height = img->height;
		int stride = width * 3;
		int offset;
		int kMax, lMax;
		char *imgImageData = img->imageData;
		struct Rgb *dstImageData = (struct Rgb*)dst->imageData;
		for (int i = 0; i < height; i += mSize) {
			kMax = i + mSize < height ? mSize : height - i;
			for (int j = 0; j < width; j += mSize) {
				r = b = g = 0;
				p = (i * width + j) * 3;
				lMax = j + mSize < width  ? mSize : width - j;
				c = kMax * lMax;
				pp = offset = p;
				for (int k = 0; k < kMax; k++) {	
					for (int l = 0; l < lMax; l++) {
						b += (unsigned char)imgImageData[pp++];
						g += (unsigned char)imgImageData[pp++];
						r += (unsigned char)imgImageData[pp++];
					}
					offset += stride;
					pp = offset;
				}
				rgb.r = r / c;
				rgb.g = g / c;
				rgb.b = b / c;
				pp = offset = i * width + j;
				for (int k = 0; k < kMax; k++) {
					for (int l = 0; l < lMax; l++) {
						dstImageData[pp++] = rgb;
					}
					offset += width;
					pp = offset;
				}
			}
		}
		cvReleaseImage(&img);
		imageView.image = [self UIImageFromIplImage:dst];
		cvReleaseImage(&dst);
#elif defined(STEP8)
		int mSize = [mosaicSize intValue];
		IplImage *img = [self CreateIplImageFromUIImage:imageView.image];
		IplImage *dst = cvCreateImage(cvGetSize(img), img->depth, img->nChannels);
		int width = img->width;
		int height = img->height;
		char *imgImageData = img->imageData;
		char *dstImageData = dst->imageData;
		
		int wBlockCnt = width / mSize;
		int hBlockCnt = height / mSize;
		
		/* 割り切れる領域 */
		mosaic(imgImageData, dstImageData, width, 0, 0, wBlockCnt, hBlockCnt, mSize, mSize, (width - mSize) * 3);
		
		/* 割り切れない領域 */
		if ( width % mSize > 0) {
			mosaic(imgImageData, dstImageData, width, wBlockCnt, 0, wBlockCnt + 1, hBlockCnt, width % mSize, mSize, (width - (width % mSize)) * 3);
		}
		if ( height % mSize > 0) {
			mosaic(imgImageData, dstImageData, width, 0, hBlockCnt, wBlockCnt, hBlockCnt + 1, mSize, height % mSize, (width - mSize) * 3);
		}
		if ( width % mSize > 0 && height % mSize > 0) {
			mosaic(imgImageData, dstImageData, width, wBlockCnt, hBlockCnt, wBlockCnt + 1, hBlockCnt + 1, width % mSize, height % mSize, (width - (width % mSize)) * 3);
		}

		cvReleaseImage(&img);
		imageView.image = [self UIImageFromIplImage:dst];
		cvReleaseImage(&dst);
#elif defined(STEP9)
		int mSize = [mosaicSize intValue];
		IplImage *img = [self CreateIplImageFromUIImage:imageView.image];
		IplImage *dst = cvCreateImage(cvGetSize(img), img->depth, img->nChannels);
		int width = img->width;
		int height = img->height;
		char *imgImageData = img->imageData;
		char *dstImageData = dst->imageData;
		
		/* 割り切れる領域 */
		mosaic2(imgImageData, dstImageData, width, height, mSize, mSize);
				
		cvReleaseImage(&img);
		imageView.image = [self UIImageFromIplImage:dst];
		cvReleaseImage(&dst);
		
#endif
		double time = [timeRecorder end];
		NSLog(@"\t%d\t%lf\tmsec",mSize, time);
		if (mSize < 128) {
			NSNumber *doubleSize = [[NSNumber alloc] initWithInt:mSize * 2]; 
			[self performSelectorInBackground:@selector(opencvMosaic:) withObject:doubleSize];
			[doubleSize release];
		}
		else {
			NSLog(@"\taverage:\t%lf\tmsec", [timeRecorder average]);
		}

	}
	[self hideProgressIndicator];
	[pool release];
}

#pragma mark -
#pragma mark IBAction

- (IBAction)loadImage:(id)sender {
	if(!actionSheetAction) {
		UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:@""
																 delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil
														otherButtonTitles:@"Use Photo from Library", @"Take Photo with Camera", @"Use Default Lena", nil];
		actionSheet.actionSheetStyle = UIActionSheetStyleDefault;
		actionSheetAction = ActionSheetToSelectTypeOfSource;
		[actionSheet showInView:self.view];
		[actionSheet release];
	}
}

- (IBAction)saveImage:(id)sender {
	if(imageView.image) {
		[self showProgressIndicator:@"Saving"];
		UIImageWriteToSavedPhotosAlbum(imageView.image, self, @selector(finishUIImageWriteToSavedPhotosAlbum:didFinishSavingWithError:contextInfo:), nil);
	}
}

- (void)finishUIImageWriteToSavedPhotosAlbum:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
	[self hideProgressIndicator];
}

- (IBAction)edgeDetect:(id)sender {
	[self showProgressIndicator:@"Detecting"];
	[self performSelectorInBackground:@selector(opencvEdgeDetect) withObject:nil];
}

- (IBAction)faceDetect:(id)sender {
	cvSetErrMode(CV_ErrModeParent);
	if(imageView.image && !actionSheetAction) {
		UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:@""
																 delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil
														otherButtonTitles:@"Bounding Box", @"Laughing Man", nil];
		actionSheet.actionSheetStyle = UIActionSheetStyleDefault;
		actionSheetAction = ActionSheetToSelectTypeOfMarks;
		[actionSheet showInView:self.view];
		[actionSheet release];
	}
}

- (IBAction)mosaic:(id)sender {
	cvSetErrMode(CV_ErrModeParent);
	[self showProgressIndicator:@"Mosaic"];
	NSNumber *mosaicSize = [[NSNumber alloc] initWithInt:2];
	[timeRecorder reset];
	[self performSelectorInBackground:@selector(opencvMosaic:) withObject:mosaicSize];
	[mosaicSize release];
}

#pragma mark -
#pragma mark UIViewControllerDelegate

- (void)viewDidLoad {
	[super viewDidLoad];
	[[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackOpaque animated:YES];
	[self loadImage:nil];

	NSURL *url = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"Tink" ofType:@"aiff"] isDirectory:NO];
	AudioServicesCreateSystemSoundID((CFURLRef)url, &alertSoundID);
	timeRecorder = [[TimeRecorder alloc] init];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
	return NO;
}

#pragma mark -
#pragma mark UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
	switch(actionSheetAction) {
		case ActionSheetToSelectTypeOfSource: {
			UIImagePickerControllerSourceType sourceType;
			if (buttonIndex == 0) {
				sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
			} else if(buttonIndex == 1) {
				sourceType = UIImagePickerControllerSourceTypeCamera;
			} else if(buttonIndex == 2) {
				NSString *path = [[NSBundle mainBundle] pathForResource:@"lena" ofType:@"jpg"];
				imageView.image = [UIImage imageWithContentsOfFile:path];
				break;
			} else {
				// Cancel
				break;
			}
			if([UIImagePickerController isSourceTypeAvailable:sourceType]) {
				UIImagePickerController *picker = [[UIImagePickerController alloc] init];
				picker.sourceType = sourceType;
				picker.delegate = self;
				picker.allowsEditing = NO;
				[self presentModalViewController:picker animated:YES];
				[picker release];
			}
			break;
		}
		case ActionSheetToSelectTypeOfMarks: {
			if(buttonIndex != 0 && buttonIndex != 1) {
				break;
			}

			UIImage *image = nil;
			if(buttonIndex == 1) {
				NSString *path = [[NSBundle mainBundle] pathForResource:@"laughing_man" ofType:@"png"];
				image = [UIImage imageWithContentsOfFile:path];
			}

			[self showProgressIndicator:@"Detecting"];
			[self performSelectorInBackground:@selector(opencvFaceDetect:) withObject:image];
			break;
		}
	}
	actionSheetAction = 0;
}

#pragma mark -
#pragma mark UIImagePickerControllerDelegate

- (UIImage *)scaleAndRotateImage:(UIImage *)image {
	static int kMaxResolution = 640;
	
	CGImageRef imgRef = image.CGImage;
	CGFloat width = CGImageGetWidth(imgRef);
	CGFloat height = CGImageGetHeight(imgRef);
	
	CGAffineTransform transform = CGAffineTransformIdentity;
	CGRect bounds = CGRectMake(0, 0, width, height);
	if (width > kMaxResolution || height > kMaxResolution) {
		CGFloat ratio = width/height;
		if (ratio > 1) {
			bounds.size.width = kMaxResolution;
			bounds.size.height = bounds.size.width / ratio;
		} else {
			bounds.size.height = kMaxResolution;
			bounds.size.width = bounds.size.height * ratio;
		}
	}
	
	CGFloat scaleRatio = bounds.size.width / width;
	CGSize imageSize = CGSizeMake(CGImageGetWidth(imgRef), CGImageGetHeight(imgRef));
	CGFloat boundHeight;
	
	UIImageOrientation orient = image.imageOrientation;
	switch(orient) {
		case UIImageOrientationUp:
			transform = CGAffineTransformIdentity;
			break;
		case UIImageOrientationUpMirrored:
			transform = CGAffineTransformMakeTranslation(imageSize.width, 0.0);
			transform = CGAffineTransformScale(transform, -1.0, 1.0);
			break;
		case UIImageOrientationDown:
			transform = CGAffineTransformMakeTranslation(imageSize.width, imageSize.height);
			transform = CGAffineTransformRotate(transform, M_PI);
			break;
		case UIImageOrientationDownMirrored:
			transform = CGAffineTransformMakeTranslation(0.0, imageSize.height);
			transform = CGAffineTransformScale(transform, 1.0, -1.0);
			break;
		case UIImageOrientationLeftMirrored:
			boundHeight = bounds.size.height;
			bounds.size.height = bounds.size.width;
			bounds.size.width = boundHeight;
			transform = CGAffineTransformMakeTranslation(imageSize.height, imageSize.width);
			transform = CGAffineTransformScale(transform, -1.0, 1.0);
			transform = CGAffineTransformRotate(transform, 3.0 * M_PI / 2.0);
			break;
		case UIImageOrientationLeft:
			boundHeight = bounds.size.height;
			bounds.size.height = bounds.size.width;
			bounds.size.width = boundHeight;
			transform = CGAffineTransformMakeTranslation(0.0, imageSize.width);
			transform = CGAffineTransformRotate(transform, 3.0 * M_PI / 2.0);
			break;
		case UIImageOrientationRightMirrored:
			boundHeight = bounds.size.height;
			bounds.size.height = bounds.size.width;
			bounds.size.width = boundHeight;
			transform = CGAffineTransformMakeScale(-1.0, 1.0);
			transform = CGAffineTransformRotate(transform, M_PI / 2.0);
			break;
		case UIImageOrientationRight:
			boundHeight = bounds.size.height;
			bounds.size.height = bounds.size.width;
			bounds.size.width = boundHeight;
			transform = CGAffineTransformMakeTranslation(imageSize.height, 0.0);
			transform = CGAffineTransformRotate(transform, M_PI / 2.0);
			break;
		default:
			[NSException raise:NSInternalInconsistencyException format:@"Invalid image orientation"];
	}
	
	UIGraphicsBeginImageContext(bounds.size);
	CGContextRef context = UIGraphicsGetCurrentContext();
	if (orient == UIImageOrientationRight || orient == UIImageOrientationLeft) {
		CGContextScaleCTM(context, -scaleRatio, scaleRatio);
		CGContextTranslateCTM(context, -height, 0);
	} else {
		CGContextScaleCTM(context, scaleRatio, -scaleRatio);
		CGContextTranslateCTM(context, 0, -height);
	}
	CGContextConcatCTM(context, transform);
	CGContextDrawImage(UIGraphicsGetCurrentContext(), CGRectMake(0, 0, width, height), imgRef);
	UIImage *imageCopy = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	
	return imageCopy;
}

- (void)imagePickerController:(UIImagePickerController *)picker
		didFinishPickingImage:(UIImage *)image
				  editingInfo:(NSDictionary *)editingInfo
{
	imageView.image = [self scaleAndRotateImage:image];
	[[picker parentViewController] dismissModalViewControllerAnimated:YES];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	[[picker parentViewController] dismissModalViewControllerAnimated:YES];
}
@end