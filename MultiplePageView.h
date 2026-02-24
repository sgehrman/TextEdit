
/*
     File: MultiplePageView.h
 Abstract: View which holds all the pages together in the multiple-page case.
 
  Version: 1.8
 

 
 */

#import <Cocoa/Cocoa.h>

@interface MultiplePageView : NSView

@property (nonatomic, copy) NSPrintInfo *printInfo;
@property (nonatomic, copy) NSColor *lineColor;
@property (nonatomic, copy) NSColor *marginColor;
@property (nonatomic, assign) NSUInteger numberOfPages;
@property (nonatomic, assign) NSTextLayoutOrientation layoutOrientation;

- (CGFloat)pageSeparatorHeight;
- (NSSize)documentSizeInPage;	/* Returns the area where the document can draw */
- (NSRect)documentRectForPageNumber:(NSUInteger)pageNumber;	/* First page is page 0 */
- (NSRect)pageRectForPageNumber:(NSUInteger)pageNumber;	/* First page is page 0 */

@end
