
/*
     File: ScalingScrollView.h
 Abstract: NSScrollView subclass to support scaling content.

  Version: 1.8



 */

#import <Cocoa/Cocoa.h>

@class NSPopUpButton;

@interface ScalingScrollView : NSScrollView

- (void)setScaleFactor:(CGFloat)factor adjustPopup:(BOOL)flag;
- (CGFloat)scaleFactor;

- (IBAction)zoomToActualSize:(id)sender;
- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;

@end
