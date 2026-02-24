
/*
     File: PrintPanelAccessoryController.h
 Abstract: PrintPanelAccessoryController is a subclass of NSViewController demonstrating how to add an accessory view to the print panel.
 
  Version: 1.8
 

 
 */

#import <Cocoa/Cocoa.h>


@interface PrintPanelAccessoryController : NSViewController <NSPrintPanelAccessorizing>

- (IBAction)changePageNumbering:(id)sender;
- (IBAction)changeWrappingToFit:(id)sender;

@property (nonatomic, assign) BOOL pageNumbering;
@property (nonatomic, assign) BOOL wrappingToFit;
@property (nonatomic, assign) BOOL showsWrappingToFit;

@end
