
/*
     File: DocumentPropertiesPanelController.m
 Abstract: "Document Properties" panel controller for TextEdit.  There is a little more code here than one would like,
 however, this code does show steps needed to implement a non-modal inspector panel using bindings, and have
 the fields in the panel correctly commit when the panel loses key, or the document it is associated with
 is saved or made non-key (inactive).
 
 This class is mostly reusable, except with the assumption that commitEditing always succeeds.
 
  Version: 1.8
 

 
 */

#import "DocumentPropertiesPanelController.h"
#import "Document.h"
#import "DocumentController.h"
#import "TextEditMisc.h"
#import "Controller.h"

@interface DocumentPropertiesPanelController ()
@property (nonatomic, strong) IBOutlet id documentObjectController;
@property (nonatomic, strong) id inspectedDocument;
@end

@implementation DocumentPropertiesPanelController

- (id)init {
    return [super initWithWindowNibName:@"DocumentProperties"];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSApp removeObserver:self forKeyPath:@"mainWindow.windowController.document"];
}

/* inspectedDocument is a KVO-compliant property, which this method manages. Anytime we hear about the mainWindow, or the mainWindow's document change, we check to see what changed.  Note that activeDocumentChanged doesn't mean document contents changed, but rather we have a new active document.
*/
- (void)activeDocumentChanged {
    id doc = [[[NSApp mainWindow] windowController] document];
    if (doc != _inspectedDocument) {
	if (_inspectedDocument) [_documentObjectController commitEditing];
	[self setValue:(doc && [doc isKindOfClass:[Document class]]) ? doc : nil forKey:@"inspectedDocument"];   
    }
}
    
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == (__bridge void *)[DocumentPropertiesPanelController class]) {
	[self activeDocumentChanged];
    } else {
	[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

/* When controls in the panel start editing, register it with the inspected document.
*/
- (void)objectDidBeginEditing:(id)editor {
    [_inspectedDocument objectDidBeginEditing:editor];
}

- (void)objectDidEndEditing:(id)editor {
    [_inspectedDocument objectDidEndEditing:editor];
}

/* We don't want to do any observing until the properties panel is brought up.
*/
- (void)windowDidLoad {
    // Once the UI is loaded, we start observing the panel itself to commit editing when it becomes inactive (loses key state)
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(documentPropertiesPanelDidResignKey:) name:NSWindowDidResignKeyNotification object:[self window]];

    // Make sure we start inspecting the document that is currently active, and start observing changes
    [self activeDocumentChanged];
    [NSApp addObserver:self forKeyPath:@"mainWindow.windowController.document" options:0 context:(__bridge void *)[DocumentPropertiesPanelController class]];

    NSWindow *window = [self window];
    [window setIdentifier:@"DocumentProperties"];
    [window setRestorationClass:[self class]];

    [super windowDidLoad];  // It's documented to do nothing, but still a good idea to invoke...
}

/* Reopen the properties window when the app's persistent state is restored. 
*/
+ (void)restoreWindowWithIdentifier:(NSString *)identifier state:(NSCoder *)state completionHandler:(void (^)(NSWindow *, NSError *))completionHandler {
    completionHandler([[(Controller *)[NSApp delegate] propertiesController] window], NULL);
}

/* Whenever the properties panel loses key status, we want to commit editing.
*/
- (void)documentPropertiesPanelDidResignKey:(NSNotification *)notification {
    [_documentObjectController commitEditing];
}

/* Since we want the panel to toggle... Note that if the window is visible and key, we order it out; otherwise we make it key.
*/
- (IBAction)toggleWindow:(id)sender {
    NSWindow *window = [self window];
    if ([window isVisible] && [window isKeyWindow]) {
	[[self window] orderOut:sender];
    } else {
	[[self window] makeKeyAndOrderFront:sender];
    }
}

/* validateMenuItem: is used to dynamically set attributes of menu items.
*/
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if ([menuItem action] == @selector(toggleWindow:)) {   // Correctly toggle the menu item for showing/hiding document properties
	// We call [self isWindowLoaded] first since it prevents [self window] from loading the nib
	validateToggleItem(menuItem, [self isWindowLoaded] && [[self window] isVisible], NSLocalizedString(@"Hide Properties", @"Title for menu item to hide the document properties panel."), NSLocalizedString(@"Show Properties", @"Title for menu item to show the document properties panel (should be the same as the initial menu item in the nib)."));
    }
    return YES;
}

@end
