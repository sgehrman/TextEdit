
/*
     File: PrintingTextView.h
 Abstract: Very simple subclass of NSTextView that allows dynamic rewrapping/resizing to accomodate
 user options in the print panel when printing. This view is used only for printing of
 "wrap-to-window" views, since "wrap-to-page" views have fixed wrapping and size already.

  Version: 1.8



 */

#import <Cocoa/Cocoa.h>
@class PrintPanelAccessoryController;

@interface PrintingTextView : NSTextView

@property(nonatomic, weak) PrintPanelAccessoryController *printPanelAccessoryController;
@property(nonatomic, assign) NSSize originalSize;
@end
