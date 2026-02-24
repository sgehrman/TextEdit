
/*
     File: DocumentPropertiesPanelController.h
 Abstract: "Document Properties" panel controller for TextEdit.  There is a little more code here than one would like,
 however, this code does show steps needed to implement a non-modal inspector panel using bindings, and have
 the fields in the panel correctly commit when the panel loses key, or the document it is associated with
 is saved or made non-key (inactive).
 
 This class is mostly reusable, except with the assumption that commitEditing always succeeds.
 
  Version: 1.8
 

 
 */

#import <Cocoa/Cocoa.h>


@interface DocumentPropertiesPanelController : NSWindowController {
    IBOutlet id documentObjectController;
    id inspectedDocument;
}

- (IBAction)toggleWindow:(id)sender;

@end
