
/*
     File: DocumentWindowController.h
 Abstract: Document's main window controller object for TextEdit.

  Version: 1.8



 */

#import "ScalingScrollView.h"
#import <Cocoa/Cocoa.h>

@interface DocumentWindowController
    : NSWindowController <NSLayoutManagerDelegate, NSTextViewDelegate>

// Convenience initializer. Loads the correct nib automatically.
- (id)init;

- (NSUInteger)numberOfPages;

- (NSView *)documentView;

- (NSTextView *)firstTextView;

- (void)breakUndoCoalescing;

/* Layout orientation sections */
- (NSArray *)layoutOrientationSections;

- (IBAction)chooseAndAttachFiles:(id)sender;

@end
