
/*
     File: PrintingTextView.h
 Abstract: Very simple subclass of NSTextView that allows dynamic rewrapping/resizing to accomodate user options in the print panel when printing.
 This view is used only for printing of "wrap-to-window" views, since "wrap-to-page" views have fixed wrapping and size already.
 
  Version: 1.8
 

 
 */

#import <Cocoa/Cocoa.h>
@class PrintPanelAccessoryController;

@interface PrintingTextView : NSTextView {
    __weak PrintPanelAccessoryController *printPanelAccessoryController;	// Accessory controller which manages user's printing choices
    NSSize originalSize;			// The original size of the text view in the window (used for non-rewrapped printing)
    NSSize previousValueOfDocumentSizeInPage;	// As user fiddles with the print panel settings, stores the last document size for which the text was relaid out
    BOOL previousValueOfWrappingToFit;		// Stores the last setting of whether to rewrap to fit page or not
}
@property (weak) PrintPanelAccessoryController *printPanelAccessoryController;
@property (assign) NSSize originalSize;
@end
