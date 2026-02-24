
/*
     File: PrintingTextView.m
 Abstract: Very simple subclass of NSTextView that allows dynamic rewrapping/resizing to accomodate user options in the print panel when printing.
 This view is used only for printing of "wrap-to-window" views, since "wrap-to-page" views have fixed wrapping and size already.
 
  Version: 1.8
 

 
 */

#import <Cocoa/Cocoa.h>
#import "PrintingTextView.h"
#import "PrintPanelAccessoryController.h"
#import "TextEditMisc.h"


@interface PrintingTextView ()
@property (nonatomic, assign) NSSize previousValueOfDocumentSizeInPage;
@property (nonatomic, assign) BOOL previousValueOfWrappingToFit;
@end

@implementation PrintingTextView

/* Override of knowsPageRange: checks printing parameters against the last invocation, and if not the same, resizes the view and relays out the text.  On first invocation, the saved size will be 0,0, which will cause the text to be laid out.
*/
- (BOOL)knowsPageRange:(NSRangePointer)range {
    NSSize documentSizeInPage = documentSizeForPrintInfo([self.printPanelAccessoryController representedObject]);
    BOOL wrappingToFit = self.printPanelAccessoryController.wrappingToFit;
    
    if (!NSEqualSizes(_previousValueOfDocumentSizeInPage, documentSizeInPage) || (_previousValueOfWrappingToFit != wrappingToFit)) {
        _previousValueOfDocumentSizeInPage = documentSizeInPage;
        _previousValueOfWrappingToFit = wrappingToFit;
        
        NSSize size = wrappingToFit ? documentSizeInPage : self.originalSize;
        [self setFrame:NSMakeRect(0.0, 0.0, size.width, size.height)];
        [[[self textContainer] layoutManager] setDefaultAttachmentScaling:wrappingToFit ? NSImageScaleProportionallyDown : NSImageScaleNone];
        [self textEditDoForegroundLayoutToCharacterIndex:NSIntegerMax];		// Make sure the whole document is laid out
    }
    return [super knowsPageRange:range];
}

@end
