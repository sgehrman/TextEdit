
/*
     File: ScalingScrollView.m
 Abstract: NSScrollView subclass to support scaling content.
 
  Version: 1.8
 

 
 */

#import <Cocoa/Cocoa.h>
#import "ScalingScrollView.h"

@implementation ScalingScrollView

- (void)awakeFromNib {
    [super awakeFromNib];
    [self setAllowsMagnification:YES];
    [self setMaxMagnification:16.0];
    [self setMinMagnification:0.25];
}

- (CGFloat)scaleFactor {
    return [self magnification];
}

- (void)setScaleFactor:(CGFloat)newScaleFactor {
    [self setMagnification:newScaleFactor];
}

- (void)setScaleFactor:(CGFloat)newScaleFactor adjustPopup:(BOOL)flag {
    [self setScaleFactor:newScaleFactor];
}

/* Action methods
*/
- (IBAction)zoomToActualSize:(id)sender {
    [[self animator] setMagnification:1.0];
}

- (IBAction)zoomIn:(id)sender {
    CGFloat scaleFactor = [self scaleFactor];
    scaleFactor = (scaleFactor > 0.4 && scaleFactor < 0.6) ? 1.0 : scaleFactor * 2.0;
    [[self animator] setMagnification:scaleFactor];
}

- (IBAction)zoomOut:(id)sender {
    CGFloat scaleFactor = [self scaleFactor];
    scaleFactor = (scaleFactor > 1.8 && scaleFactor < 2.2) ? 1.0 : scaleFactor / 2.0;
    [[self animator] setMagnification:scaleFactor];
}

/* Reassure AppKit that ScalingScrollView supports live resize content preservation, even though it's a subclass that could have modified NSScrollView in such a way as to make NSScrollView's live resize content preservation support inoperative. By default this is disabled for NSScrollView subclasses.
*/
- (BOOL)preservesContentDuringLiveResize {
    return [self drawsBackground];
}

@end
