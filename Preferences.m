
/*
     File: Preferences.m
 Abstract: Preferences controller, subclass of NSWindowController. Since the switch to a bindings-based preferences interface, the class has become a lot simpler; its only duties now are to manage the user fonts for rich and plain text documents, translate HTML saving options from backwards-compatible defaults values into pop-up menu item tags, and revert everything to the initial defaults if the user so chooses.
 
 The Preferences instance also acts as a delegate for the window, in order to validate edits before it closes, and for the two text fields bound to the window size in characters, so that invalid entries trigger a reset to a field's previous value.
 
  Version: 1.8
 

 
 */

#import <Cocoa/Cocoa.h>
#import "Preferences.h"
#import "EncodingManager.h"
#import "FontNameTransformer.h"
#import "TextEditDefaultsKeys.h"
#import "Controller.h"

@interface Preferences ()
@property (nonatomic, assign) BOOL changingRTFFont;
@property (nonatomic, assign) NSInteger originalDimensionFieldValue;
@end

@implementation Preferences

- (id)init {
    return [super initWithWindowNibName:@"Preferences"];
}

- (void)windowDidLoad {
    NSWindow *window = [self window];
    [window setHidesOnDeactivate:NO];
    [window setExcludedFromWindowsMenu:YES];
    [window setIdentifier:@"Preferences"];
    [window setRestorationClass:[self class]];
}

/* Reopen the preferences window when the app's persistent state is restored. 
*/
+ (void)restoreWindowWithIdentifier:(NSString *)identifier state:(NSCoder *)state completionHandler:(void (^)(NSWindow *, NSError *))completionHandler {
    completionHandler([[(Controller *)[NSApp delegate] preferencesController] window], NULL);
}


#pragma mark *** Font changing code ***

- (IBAction)changeRichTextFont:(id)sender {
    // validate whatever's currently being edited first
    if ([[self window] makeFirstResponder:nil]) {
        _changingRTFFont = YES;
        NSFontManager *fontManager = [NSFontManager sharedFontManager];
        [fontManager setSelectedFont:[self richTextFont] isMultiple:NO];
        [fontManager orderFrontFontPanel:self];
    }
}

- (IBAction)changePlainTextFont:(id)sender {
    // validate whatever's currently being edited first
    if ([[self window] makeFirstResponder:nil]) {
        _changingRTFFont = NO;    
        NSFontManager *fontManager = [NSFontManager sharedFontManager];
        [fontManager setSelectedFont:[self plainTextFont] isMultiple:NO];
        [fontManager orderFrontFontPanel:self];
    }
}

- (void)changeFont:(id)fontManager {
    if (_changingRTFFont) {
        [self setRichTextFont:[fontManager convertFont:[self richTextFont]]];
    } else {
        [self setPlainTextFont:[fontManager convertFont:[self plainTextFont]]];
    }
}

- (void)setRichTextFont:(NSFont *)newFont {
    [NSFont setUserFont:newFont];
}

- (void)setPlainTextFont:(NSFont *)newFont {
    [NSFont setUserFixedPitchFont:newFont];
}

- (NSFont *)richTextFont {
    return [NSFont userFontOfSize:0.0];
}

- (NSFont *)plainTextFont {
    return [NSFont userFixedPitchFontOfSize:0.0];
}

#pragma mark *** HTML document type and styling code ***

/* The user chooses the HTML document type using a popup button, but the actual type is represented as a two-bit bitfield, where one bit represents whether or not to use a transitional DTD and another bit determines whether or not to use XHTML. The popup button uses the bitfield's integer value as its tag.
 */
- (HTMLDocumentTypeOptions)HTMLDocumentType {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    HTMLDocumentTypeOptions type = 0;
    
    if ([defaults boolForKey:UseXHTMLDocType]) type |= HTMLDocumentTypeOptionUseXHTML;
    if ([defaults boolForKey:UseTransitionalDocType]) type |= HTMLDocumentTypeOptionUseTransitional;
    
    return type;
}

- (void)setHTMLDocumentType:(HTMLDocumentTypeOptions)newType {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    [defaults setBool:((newType & HTMLDocumentTypeOptionUseXHTML) == HTMLDocumentTypeOptionUseXHTML) forKey:UseXHTMLDocType];
    [defaults setBool:((newType & HTMLDocumentTypeOptionUseTransitional) == HTMLDocumentTypeOptionUseTransitional) forKey:UseTransitionalDocType];
}

/* The style mode is how style information is encoded when saving HTML: using embedded or inline CSS, or using older HTML tags and attributes. For backwards compatibility this information is stored in user defaults as two boolean values, rather than a style mode name or enumerated integer value.
 */
- (HTMLStylingMode)HTMLStylingMode {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    if ([defaults boolForKey:UseEmbeddedCSS]) {
        return HTMLStylingUseEmbeddedCSS;
    } else if ([defaults boolForKey:UseInlineCSS]) {
        return HTMLStylingUseInlineCSS;
    } else {
        return HTMLStylingUseNoCSS;
    }
}

- (void)setHTMLStylingMode:(HTMLStylingMode)newMode {
    BOOL useEmbedded = NO;
    BOOL useInline = NO;
    
    switch (newMode) {
        case HTMLStylingUseEmbeddedCSS:
            useEmbedded = YES;
            break;
        case HTMLStylingUseInlineCSS:
            useInline = YES;
            break;
            // ignore default case
    }
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:useEmbedded forKey:UseEmbeddedCSS];
    [defaults setBool:useInline forKey:UseInlineCSS];
}

#pragma mark *** Reverting to defaults ***

- (IBAction)revertToDefault:(id)sender {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    [self willChangeValueForKey:@"HTMLDocumentType"];
    [defaults removeObjectForKey:UseXHTMLDocType];
    [defaults removeObjectForKey:UseTransitionalDocType];
    [self didChangeValueForKey:@"HTMLDocumentType"];
    
    [self willChangeValueForKey:@"HTMLStylingMode"];
    [defaults removeObjectForKey:UseEmbeddedCSS];
    [defaults removeObjectForKey:UseInlineCSS];
    [self didChangeValueForKey:@"HTMLStylingMode"];
    
    [self setRichTextFont:nil];
    [self setPlainTextFont:nil];
    
    [[NSUserDefaultsController sharedUserDefaultsController] revertToInitialValues:nil];    // For the rest of the defaults
}

#pragma mark *** Window delegation ***

/* We do this to catch the case where the user enters a value into one of the text fields but closes the window without hitting enter or tab.
 */
- (BOOL)windowShouldClose:(NSWindow *)window {
    return [window makeFirstResponder:nil]; // validate editing
}

#pragma mark *** Window size field delegation ***

- (void)controlTextDidBeginEditing:(NSNotification *)note {
    _originalDimensionFieldValue = [[note object] integerValue];
}

/* Handle the case when the user enters a ridiculous value for the window size. We just set it back to what it started as.
 */
- (BOOL)control:(NSControl *)control didFailToFormatString:(NSString *)string errorDescription:(NSString *)error {
    [control setIntegerValue:_originalDimensionFieldValue];
    return YES;
}


@end
