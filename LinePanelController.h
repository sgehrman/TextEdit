
/*
     File: LinePanelController.h
 Abstract: "Select Line" panel controller for TextEdit.
 Enables selecting a single line, range of lines, from start or relative to current selected range.
 
  Version: 1.8
 

 
 */

#import <Cocoa/Cocoa.h>


@interface LinePanelController : NSWindowController {
    IBOutlet NSTextField *lineField;
}

- (IBAction)lineFieldChanged:(id)sender;
- (IBAction)selectClicked:(id)sender;

@end
