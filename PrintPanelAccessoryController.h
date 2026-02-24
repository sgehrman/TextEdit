
/*
     File: PrintPanelAccessoryController.h
 Abstract: PrintPanelAccessoryController is a subclass of NSViewController demonstrating how to add an accessory view to the print panel.
 
  Version: 1.8
 

 
 */

#import <Cocoa/Cocoa.h>


@interface PrintPanelAccessoryController : NSViewController <NSPrintPanelAccessorizing> {
    BOOL showsWrappingToFit;
    BOOL wrappingToFit;
}

- (IBAction)changePageNumbering:(id)sender;
- (IBAction)changeWrappingToFit:(id)sender;

@property BOOL pageNumbering;
@property BOOL wrappingToFit;
@property BOOL showsWrappingToFit;

@end
