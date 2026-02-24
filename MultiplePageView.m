
/*
     File: MultiplePageView.m
 Abstract: View which holds all the pages together in the multiple-page case.

  Version: 1.8



 */

#import "MultiplePageView.h"
#import "TextEditMisc.h"
#import <Cocoa/Cocoa.h>

@implementation MultiplePageView

- (id)initWithFrame:(NSRect)rect {
  if ((self = [super initWithFrame:rect])) {
    _numberOfPages = 0;
    [self setLineColor:[NSColor lightGrayColor]];
    [self setMarginColor:[NSColor whiteColor]];
    /* This will set the frame to be whatever's appropriate... */
    [self setPrintInfo:[NSPrintInfo sharedPrintInfo]];
  }
  return self;
}

- (BOOL)isFlipped {
  return YES;
}

- (BOOL)isOpaque {
  return YES;
}

- (void)updateFrame {
  if ([self superview]) {
    NSRect rect = NSZeroRect;
    rect.size = [_printInfo paperSize];
    if (NSTextLayoutOrientationHorizontal == _layoutOrientation) {
      rect.size.height = rect.size.height * _numberOfPages;
      if (_numberOfPages > 1) {
        rect.size.height += [self pageSeparatorHeight] * (_numberOfPages - 1);
      }
    } else {
      rect.size.width = rect.size.width * _numberOfPages;
      if (_numberOfPages > 1) {
        rect.size.width += [self pageSeparatorHeight] * (_numberOfPages - 1);
      }
    }
    rect.size = [self convertSize:rect.size toView:[self superview]];
    [self setFrame:rect];
  }
}

- (void)setPrintInfo:(NSPrintInfo *)anObject {
  if (_printInfo != anObject) {
    _printInfo = [anObject copy];
    [self updateFrame];
    [self setNeedsDisplay:YES]; /* Because the page size or margins might change (could optimize
                                   this) */
  }
}

- (void)setNumberOfPages:(NSUInteger)num {
  if (_numberOfPages != num) {
    NSRect oldFrame = [self frame];
    NSRect newFrame;
    _numberOfPages = num;
    [self updateFrame];
    newFrame = [self frame];
    if (newFrame.size.height > oldFrame.size.height) {
      [self
          setNeedsDisplayInRect:NSMakeRect(oldFrame.origin.x, NSMaxY(oldFrame), oldFrame.size.width,
                                           NSMaxY(newFrame) - NSMaxY(oldFrame))];
    }
  }
}

- (CGFloat)pageSeparatorHeight {
  return 5.0;
}

- (NSSize)documentSizeInPage {
  return documentSizeForPrintInfo(_printInfo);
}

- (NSRect)documentRectForPageNumber:(NSUInteger)pageNumber { /* First page is page 0, of course! */
  NSRect rect = [self pageRectForPageNumber:pageNumber];
  rect.origin.x += [_printInfo leftMargin] - defaultTextPadding();
  rect.origin.y += [_printInfo topMargin];
  rect.size = [self documentSizeInPage];
  return rect;
}

- (NSRect)pageRectForPageNumber:(NSUInteger)pageNumber {
  NSRect rect;
  rect.size = [_printInfo paperSize];
  rect.origin = [self frame].origin;

  if (NSTextLayoutOrientationHorizontal == _layoutOrientation) {
    rect.origin.y += ((rect.size.height + [self pageSeparatorHeight]) * pageNumber);
  } else {
    rect.origin.x += (NSWidth([self bounds]) -
                      ((rect.size.width + [self pageSeparatorHeight]) * (pageNumber + 1)));
  }
  return rect;
}

/* For locations on the page separator right after a page, returns that page number.  Same for any
 * locations on the empty (gray background) area to the side of a page. Will return 0 or numPages-1
 * for locations beyond the ends. Results are 0-based.
 */
- (NSUInteger)pageNumberForPoint:(NSPoint)loc {
  NSUInteger pageNumber;
  if (NSTextLayoutOrientationHorizontal == _layoutOrientation) {
    if (loc.y < 0) {
      pageNumber = 0;
    } else if (loc.y >= [self bounds].size.height) {
      pageNumber = _numberOfPages - 1;
    } else {
      pageNumber = loc.y / ([_printInfo paperSize].height + [self pageSeparatorHeight]);
    }
  } else {
    if (loc.x < 0) {
      pageNumber = _numberOfPages - 1;
    } else if (loc.x >= [self bounds].size.width) {
      pageNumber = 0;
    } else {
      pageNumber = (NSWidth([self bounds]) - loc.x) /
                   ([_printInfo paperSize].width + [self pageSeparatorHeight]);
    }
  }
  return pageNumber;
}

- (void)setLineColor:(NSColor *)color {
  if (color != _lineColor) {
    _lineColor = [color copy];
    [self setNeedsDisplay:YES];
  }
}

- (void)setMarginColor:(NSColor *)color {
  if (color != _marginColor) {
    _marginColor = [color copy];
    [self setNeedsDisplay:YES];
  }
}

- (void)setLayoutOrientation:(NSTextLayoutOrientation)orientation {
  if (orientation != _layoutOrientation) {
    _layoutOrientation = orientation;

    [self updateFrame];
  }
}

- (void)drawRect:(NSRect)rect {
  if ([[NSGraphicsContext currentContext] isDrawingToScreen]) {
    NSSize paperSize = [_printInfo paperSize];
    NSUInteger firstPage;
    NSUInteger lastPage;
    NSUInteger cnt;

    if (NSTextLayoutOrientationHorizontal == _layoutOrientation) {
      firstPage = NSMinY(rect) / (paperSize.height + [self pageSeparatorHeight]);
      lastPage = NSMaxY(rect) / (paperSize.height + [self pageSeparatorHeight]);
    } else {
      firstPage = _numberOfPages - (NSMaxX(rect) / (paperSize.width + [self pageSeparatorHeight]));
      lastPage = _numberOfPages - (NSMinX(rect) / (paperSize.width + [self pageSeparatorHeight]));
    }

    [_marginColor set];
    NSRectFill(rect);

    [_lineColor set];
    for (cnt = firstPage; cnt <= lastPage; cnt++) {
      // Draw boundary around the page, making sure it doesn't overlap the document area in terms of
      // pixels
      NSRect docRect =
          NSInsetRect([self centerScanRect:[self documentRectForPageNumber:cnt]], -1.0, -1.0);
      NSFrameRectWithWidth(docRect, 1.0);
    }

    if ([[self superview] isKindOfClass:[NSClipView class]]) {
      NSColor *backgroundColor = [(NSClipView *)[self superview] backgroundColor];
      [backgroundColor set];
      for (cnt = firstPage; cnt <= lastPage; cnt++) {
        NSRect pageRect = [self pageRectForPageNumber:cnt];
        NSRect separatorRect;
        if (NSTextLayoutOrientationHorizontal == _layoutOrientation) {
          separatorRect = NSMakeRect(NSMinX(pageRect), NSMaxY(pageRect), NSWidth(pageRect),
                                     [self pageSeparatorHeight]);
        } else {
          separatorRect = NSMakeRect(NSMaxX(pageRect), NSMinY(pageRect), [self pageSeparatorHeight],
                                     NSHeight(pageRect));
        }
        NSRectFill(separatorRect);
      }
    }
  }
}

/**** Smart magnification ****/

- (NSRect)rectForSmartMagnificationAtPoint:(NSPoint)location inRect:(NSRect)visibleRect {
  NSRect result;
  NSUInteger pageNumber = [self pageNumberForPoint:location];
  NSRect documentRect = NSInsetRect([self documentRectForPageNumber:pageNumber], -3.0,
                                    -3.0); // We use -3 to show a bit of the margins
  NSRect pageRect = [self pageRectForPageNumber:pageNumber];

  if (NSPointInRect(
          location,
          documentRect)) { // Smart magnify on page contents; return the page contents rect
    result = documentRect;
  } else if (NSPointInRect(location, pageRect)) { // Smart magnify on page margins; return the page
                                                  // rect (not including separator area)
    result = pageRect;
  } else { // Smart magnify between pages, or the empty area beyond the side or bottom/top of the
           // page; return the extended area for the page
    result = pageRect;
    if (NSTextLayoutOrientationHorizontal == _layoutOrientation) {
      if (NSMaxX(visibleRect) > NSMaxX(pageRect)) {
        result.size.width = NSMaxX(visibleRect); // include area to the right of the paper
      }
      if (pageNumber + 1 < _numberOfPages) {
        result.size.height += [self pageSeparatorHeight];
      }
      if (location.y > NSMaxY(result)) {
        result.size.height =
            ceil(location.y - result.origin.y); // extend the rect out to include location
      }
    } else {
      if (NSMaxY(visibleRect) > NSMaxY(pageRect)) {
        result.size.height = NSMaxY(visibleRect); // include area below the paper
      }
      if (pageNumber + 1 < _numberOfPages) {
        result.size.width += [self pageSeparatorHeight];
      }
      if (location.x > NSMaxX(result)) {
        result.size.width =
            ceil(location.x - result.origin.x); // extend the rect out to include location
      }
    }
  }
  return result;
}

/**** Printing support... ****/

- (BOOL)knowsPageRange:(NSRangePointer)aRange {
  aRange->length = [self numberOfPages];
  return YES;
}

- (NSRect)rectForPage:(NSInteger)page {
  return [self
      documentRectForPageNumber:page - 1]; /* Our page numbers start from 0; the kit's from 1 */
}

/* This method makes sure that we center the view on the page. By default, the text view "bleeds"
 * into the margins by defaultTextPadding() as a way to provide padding around the editing area. If
 * we don't do anything special, the text view appears at the margin, which causes the text to be
 * offset on the page by defaultTextPadding(). This method makes sure the text is centered.
 */
- (NSPoint)locationOfPrintRect:(NSRect)rect {
  NSSize paperSize = [_printInfo paperSize];
  return NSMakePoint((paperSize.width - rect.size.width) / 2.0,
                     (paperSize.height - rect.size.height) / 2.0);
}

@end

NSSize documentSizeForPrintInfo(NSPrintInfo *printInfo) {
  NSSize paperSize = [printInfo paperSize];
  paperSize.width -=
      ([printInfo leftMargin] + [printInfo rightMargin]) - defaultTextPadding() * 2.0;
  paperSize.height -= ([printInfo topMargin] + [printInfo bottomMargin]);
  return paperSize;
}
