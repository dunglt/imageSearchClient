//
//  MainCameraViewController.m
//  imageSearchClient
//
//  Created by sonson on 2015/03/12.
//  Copyright (c) 2015年 DENSO IT Laboratory, Inc. All rights reserved.
//

#import "MainCameraViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>

static CGColorSpaceRef sharedColorSpace = NULL;

@implementation NSBundle(MainCameraViewController)

+ (id)infoValueFromMainBundleForKey:(NSString*)key {
	if ([[[self mainBundle] localizedInfoDictionary] objectForKey:key])
		return [[[self mainBundle] localizedInfoDictionary] objectForKey:key];
	return [[[self mainBundle] infoDictionary] objectForKey:key];
}

@end

@implementation NSMutableData(MainCameraViewController)

+ (NSString*)multipartBoundary {
	return @"0xKhTmLbOuNdArY";
}

+ (NSMutableData*)mutableDataForMultipart {
	NSMutableData *data = [NSMutableData data];
	[data appendData:[[NSString stringWithFormat:@"--%@\r\n", [NSMutableData multipartBoundary]] dataUsingEncoding:NSUTF8StringEncoding]];
	return data;
}

- (void)appendPartWithData:(NSData*)data name:(NSString*)name {
	[self appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", name] dataUsingEncoding:NSUTF8StringEncoding]];
	[self appendData:data];
	[self appendData:[[NSString stringWithFormat:@"\r\n--%@\r\n", [NSMutableData multipartBoundary]] dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)appendPartWithFileData:(NSData*)data name:(NSString*)name filename:(NSString*)filename contentType:(NSString*)contentType {
	[self appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n", name, filename] dataUsingEncoding:NSUTF8StringEncoding]];
	[self appendData:[[NSString stringWithFormat:@"Content-Type: %@\r\n\r\n", contentType] dataUsingEncoding:NSUTF8StringEncoding]];
	[self appendData:data];
	[self appendData:[[NSString stringWithFormat:@"\r\n--%@\r\n", [NSMutableData multipartBoundary]] dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)finalizeMultipart {
	if ([self length] > 4) {
		char *p = (char*)([self bytes] + [self length] - 4);
		if (!strncmp(p, "--\r\n", 4)) {
			NSLog(@"out");
		}
		else {
			[self replaceBytesInRange:NSMakeRange([self length] - 2, 2) withBytes:"--"];
			[self appendBytes:"\r\n" length:3];
		}
	}
}

@end

@interface MainCameraViewController () <AVCaptureVideoDataOutputSampleBufferDelegate> {
	size_t							intrinsicBufferWidth;
	size_t							intrinsicBufferHeight;
	
	// Image buffer
	unsigned char					*buffer;
	unsigned char					*rgbBuffer;
	CGDataProviderRef				dataProvider;
	
	// UI
	IBOutlet UIImageView			*imageView;
	IBOutlet UIView					*resultView;
	IBOutlet UILabel				*UUIDLabel;
	NSTimer							*captureTimer;
}

@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureDevice *inputDevice;

@property (nonatomic, readonly) size_t imageWidth;
@property (nonatomic, readonly) size_t imageHeight;
@property (nonatomic, readonly) size_t bufferWidth;
@property (nonatomic, readonly) size_t bufferHeight;

@end

@implementation MainCameraViewController

+ (CGColorSpaceRef)sharedColorSpace {
	if (sharedColorSpace == NULL) {
		sharedColorSpace = CGColorSpaceCreateDeviceRGB();
		NSAssert(sharedColorSpace != NULL, @"CGColorSpaceCreateDeviceRGB does not work.");
	}
	return sharedColorSpace;
}

- (size_t)imageWidth {
	return  intrinsicBufferHeight;
}

- (size_t)imageHeight {
	return  intrinsicBufferWidth;
}

- (size_t)bufferWidth {
	return  intrinsicBufferWidth;
}

- (size_t)bufferHeight {
	return  intrinsicBufferHeight;
}

- (NSTimeInterval)timeIntervalToStartAutoFocusing {
	return 0.5;
}

- (void)startTimer {
	captureTimer = [NSTimer scheduledTimerWithTimeInterval:[self timeIntervalToStartAutoFocusing]
													target:self
												  selector:@selector(fired:)
												  userInfo:nil
												   repeats:NO];
}

- (IBAction)close:(id)sender {
	[UIView animateWithDuration:0.4
					 animations:^{
						 resultView.alpha = 0;
					 }
					 completion:^(BOOL finished) {
						 resultView.alpha = 0;
						 [self startTimer];
					 }];
}

- (void)didReceiveResponse:(NSHTTPURLResponse*)response responseBody:(NSData*)responseBody {
	NSDictionary *json = nil;
	if (responseBody != nil) {
		json = [NSJSONSerialization JSONObjectWithData:responseBody options:0 error:0];
	}
	if (response.statusCode == 200 && json != nil) {
		// recognize
		[self openResult:json];
	}
	else if (response.statusCode == 404) {
		// not found
		[self startTimer];
	}
	else {
		// error
		[self startTimer];
	}
}

- (void)postImage:(NSData*)imageBinary {
	// user information
	NSString *server = [NSBundle infoValueFromMainBundleForKey:@"ImageSearchServer"];
	NSString *key = [NSBundle infoValueFromMainBundleForKey:@"ImageSearchAPIKey"];
	
	// prepare request object
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@/photos/search.json", server]];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	[request setHTTPMethod:@"POST"];
	[request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", [NSMutableData multipartBoundary]] forHTTPHeaderField:@"Content-Type"];
	NSMutableData *postData = [NSMutableData mutableDataForMultipart];
	[postData appendPartWithFileData:imageBinary name:@"img" filename:@"post.jpg" contentType:@"image/JPEG"];
	[postData appendPartWithData:[key dataUsingEncoding:NSUTF8StringEncoding] name:@"key"];
	[postData finalizeMultipart];
	[request setHTTPBody:postData];
	
	NSURLResponse *response = nil;
	NSError *error = nil;
	NSData *responseBody = [NSURLConnection sendSynchronousRequest:request
												 returningResponse:&response
															 error:&error];
	dispatch_sync(dispatch_get_main_queue(), ^{
		[self didReceiveResponse:(NSHTTPURLResponse*)response responseBody:responseBody];
	});
}

- (void)didFinishAutoFocus {
	NSData *data = UIImageJPEGRepresentation(imageView.image, 1);
	if (data) {
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			[self postImage:data];
		});
	}
}

- (void)focusCenter {
	double focus_x = 0.5;
	double focus_y = 0.5;
	
	if ([self.inputDevice lockForConfiguration:nil]) {
		if ([self.inputDevice isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
			[self.inputDevice setFocusMode:AVCaptureFocusModeAutoFocus];
			[self.inputDevice setFocusPointOfInterest:CGPointMake(focus_x,focus_y)];
		}
		if ([self.inputDevice isExposureModeSupported:AVCaptureExposureModeAutoExpose]){
			[self.inputDevice setExposureMode:AVCaptureExposureModeAutoExpose];
			[self.inputDevice setExposurePointOfInterest:CGPointMake(focus_x,focus_y)];
		}
		[self.inputDevice unlockForConfiguration];
	}
}

- (void)openResult:(NSDictionary*)result {
	resultView.hidden = NO;
	resultView.alpha = 0;
	UUIDLabel.text = result[@"photo_uuid"];
	[UIView animateWithDuration:0.2 animations:^{
		resultView.alpha = 1;
	}];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if( [keyPath isEqualToString:@"adjustingFocus"] ){
		BOOL adjustingFocus = [ [change objectForKey:NSKeyValueChangeNewKey] isEqualToNumber:[NSNumber numberWithInt:1] ];
		NSLog(@"Is adjusting focus? %@", adjustingFocus ? @"YES" : @"NO" );
		NSLog(@"Change dictionary: %@", change);
		if (!adjustingFocus)
			[self didFinishAutoFocus];
	}
}


- (void)updateImageBuffer {
	
	NSAssert(buffer != NULL, @"buffer is not allocated.");
	NSAssert(rgbBuffer != NULL, @"rgbBuffer is not allocated.");
	NSAssert(dataProvider != NULL, @"dataProvider is not allocated.");
	
	for (int y = 0; y < self.imageHeight; y++) {
		for (int x = 0; x < self.imageWidth; x++) {
			*(rgbBuffer + y * 4 * self.imageWidth + 4 * (self.imageWidth - x - 1) + 0) = *(buffer + x * self.imageHeight * 4 + 4 * y + 0);
			*(rgbBuffer + y * 4 * self.imageWidth + 4 * (self.imageWidth - x - 1) + 1) = *(buffer + x * self.imageHeight * 4 + 4 * y + 1);
			*(rgbBuffer + y * 4 * self.imageWidth + 4 * (self.imageWidth - x - 1) + 2) = *(buffer + x * self.imageHeight * 4 + 4 * y + 2);
			*(rgbBuffer + y * 4 * self.imageWidth + 4 * (self.imageWidth - x - 1) + 3) = *(buffer + x * self.imageHeight * 4 + 4 * y + 3);
		}
	}
	
	// Create a bitmap image from data supplied by the data provider.
	CGImageRef cgImage = CGImageCreate(self.imageWidth, self.imageHeight, 8, 32, self.imageWidth * 4,
									   [MainCameraViewController sharedColorSpace], kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little,
									   dataProvider, NULL, true, kCGRenderingIntentDefault);
	
	// update preview
	imageView.image = [UIImage imageWithCGImage:cgImage];
	
	CGImageRelease(cgImage);
}

- (void)initCapture {
	NSString *sessionPreset = nil;
	int pixelFormat = 0;
	
	sessionPreset = AVCaptureSessionPresetMedium;
	
	pixelFormat = kCVPixelFormatType_32BGRA;
	
	NSError *error = nil;
	
	// make capture session
	self.captureSession = [[AVCaptureSession alloc] init];
	
	// get default video device
	AVCaptureDevice * videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	
	// setup video input
	AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
	
	// setup video output
	NSDictionary *settingInfo = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:pixelFormat] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
	
	AVCaptureVideoDataOutput * videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
	[videoDataOutput setAlwaysDiscardsLateVideoFrames:YES];
	[videoDataOutput setVideoSettings:settingInfo];
	
	[videoDataOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
	
	int flags = NSKeyValueObservingOptionNew;
	[videoDevice addObserver:self forKeyPath:@"adjustingFocus" options:flags context:nil];
	self.inputDevice = videoDevice;
	
	// attach video to session
	[self.captureSession beginConfiguration];
	[self.captureSession addInput:videoInput];
	[self.captureSession addOutput:videoDataOutput];
	[self.captureSession setSessionPreset:sessionPreset];
	[self.captureSession commitConfiguration];
}

- (void)allocateCBufferWithCVImageBufferRef:(CVImageBufferRef)imageBuffer {
	if (rgbBuffer == NULL) {
		
		NSAssert(buffer == NULL, @"buffer has already been allocated.");
		NSAssert(rgbBuffer == NULL,@"rgbBuffer has already been allocated.");
		NSAssert(dataProvider == NULL, @"dataProvider has already been allocated.");
		
		intrinsicBufferWidth = CVPixelBufferGetWidth(imageBuffer);
		intrinsicBufferHeight = CVPixelBufferGetHeight(imageBuffer);
		
		if (rgbBuffer == NULL)
			rgbBuffer = (unsigned char*)malloc(sizeof(unsigned char) * self.bufferWidth * self.bufferHeight * 4);
		
		if (dataProvider == NULL)
			dataProvider = CGDataProviderCreateWithData(NULL, rgbBuffer, self.bufferWidth * self.bufferHeight * 4, NULL);
		
		if (buffer == NULL)
			buffer = (unsigned char*)malloc(sizeof(unsigned char) * self.bufferWidth * self.bufferHeight * 4);
	}
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
	CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
	
	CVPixelBufferLockBaseAddress(imageBuffer, 0);
	
	unsigned char* baseAddress = (unsigned char *)CVPixelBufferGetBaseAddress(imageBuffer);
	
	[self allocateCBufferWithCVImageBufferRef:imageBuffer];
	
	memcpy(buffer, baseAddress, sizeof(unsigned char) * self.bufferWidth * self.bufferHeight * 4);
	
	CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
	
	[self updateImageBuffer];
}

#pragma mark - Timer

- (void)fired:(NSTimer*)timer {
	captureTimer = nil;
	[self focusCenter];
}

#pragma mark - UIViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	[self initCapture];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[self.captureSession startRunning];
	[self startTimer];
}

@end
