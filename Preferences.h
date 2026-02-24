
/*
     File: Preferences.h
 Abstract: Preferences controller, subclass of NSWindowController. Since the switch to a bindings-based preferences interface, the class has become a lot simpler; its only duties now are to manage the user fonts for rich and plain text documents, translate HTML saving options from backwards-compatible defaults values into pop-up menu item tags, and revert everything to the initial defaults if the user so chooses.
 
 The Preferences instance also acts as a delegate for the window, in order to validate edits before it closes, and for the two text fields bound to the window size in characters, so that invalid entries trigger a reset to a field's previous value.
 
  Version: 1.8
 

 
 */

#import <Cocoa/Cocoa.h>

enum {
    HTMLDocumentTypeOptionUseTransitional = (1 << 0),
    HTMLDocumentTypeOptionUseXHTML = (1 << 1)
};
typedef NSUInteger HTMLDocumentTypeOptions;

enum {
    HTMLStylingUseEmbeddedCSS = 0,
    HTMLStylingUseInlineCSS = 1,
    HTMLStylingUseNoCSS = 2
};
typedef NSInteger HTMLStylingMode;

@interface Preferences : NSWindowController
- (IBAction)revertToDefault:(id)sender;    

- (IBAction)changeRichTextFont:(id)sender;	/* Request to change the rich text font */
- (IBAction)changePlainTextFont:(id)sender;	/* Request to change the plain text font */
- (void)changeFont:(id)fontManager;	/* Sent by the font manager */

- (NSFont *)richTextFont;
- (void)setRichTextFont:(NSFont *)newFont;
- (NSFont *)plainTextFont;
- (void)setPlainTextFont:(NSFont *)newFont;

@end
