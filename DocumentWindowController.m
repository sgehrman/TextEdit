
/*
     File: DocumentWindowController.m
 Abstract: Document's main window controller object for TextEdit.

  Version: 1.8



 */

#import "DocumentWindowController.h"
#import "Document.h"
#import "MultiplePageView.h"
#import "TextEditDefaultsKeys.h"
#import "TextEditErrors.h"
#import "TextEditMisc.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface DocumentWindowController () <NSWindowDelegate>
@property(nonatomic, strong) NSScrollView *scrollView;
@property(nonatomic, strong) NSLayoutManager *layoutMgr;
@property(nonatomic, assign) BOOL hasMultiplePages;


@property(nonatomic, assign) NSInteger addingPageCount;
@end

@interface DocumentWindowController (Private)

- (void)setDocument:
    (Document *)doc; // Overridden with more specific type. Expects Document instance.

- (void)setupInitialTextViewSharedState;
- (void)setupTextViewForDocument;
- (void)setupWindowForDocument;
- (void)setupPagesViewForLayoutOrientation:(NSTextLayoutOrientation)orientation;

- (void)updateForRichTextAndRulerState:(BOOL)rich;
- (void)autosaveIfNeededThenToggleRich;
- (void)toggleRichWithNewFileType:(NSString *)fileType;



- (void)addPage;
- (void)removePage;
- (void)_syncPages;
- (void)_handleLayoutForContainer:(NSTextContainer *)textContainer
                            atEnd:(BOOL)layoutFinishedFlag
                    layoutManager:(NSLayoutManager *)layoutManager;

- (NSTextView *)firstTextView;

- (void)printInfoUpdated;

- (void)setHasMultiplePages:(BOOL)pages;

@end

@implementation DocumentWindowController

- (id)init {
  if (self = [super initWithWindowNibName:@""]) {
    _layoutMgr = [[NSLayoutManager alloc] init];
    [_layoutMgr setDelegate:self];
    [_layoutMgr setAllowsNonContiguousLayout:YES];
  }
  return self;
}

- (void)loadWindow {
  // Window: titled, closable, miniaturizable, resizable. Not visible at launch.
  NSWindow *window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(241, 745, 494, 357)
                styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                           NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                  backing:NSBackingStoreBuffered
                    defer:YES];
  [window setMinSize:NSMakeSize(100, 14)];
  [window setDelegate:self];
  [window setReleasedWhenClosed:NO];
  [window setTabbingMode:NSWindowTabbingModeAutomatic];

  NSScrollView *scrollView =
      [[NSScrollView alloc] initWithFrame:[[window contentView] bounds]];
  [scrollView setBorderType:NSNoBorder];
  [scrollView setTranslatesAutoresizingMaskIntoConstraints:NO];
  [scrollView setHasVerticalScroller:YES];
  [scrollView setHasHorizontalScroller:NO];
  [scrollView setAllowsMagnification:YES];
  [scrollView setMaxMagnification:16.0];
  [scrollView setMinMagnification:0.25];

  NSView *contentView = [window contentView];
  [contentView addSubview:scrollView];
  NSLayoutGuide *safeArea = contentView.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [scrollView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor],
    [scrollView.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor],
    [scrollView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
    [scrollView.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor],
  ]];
  _scrollView = scrollView;

  [self setWindow:window];
}

- (void)dealloc {
  if ([self document]) {
    [self setDocument:nil];
  }

  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_syncPages) object:nil];

  [[NSNotificationCenter defaultCenter] removeObserver:self];

  [[self firstTextView] removeObserver:self forKeyPath:@"backgroundColor"];
}

/* This method can be called in three different situations (number three is a
  special TextEdit case): 1) When the window controller is created and set up
  with a new or opened document. (!oldDoc && doc) 2) When the document is
  closed, and the controller is about to be destroyed (oldDoc && !doc) 3) When
  the window controller is assigned to another document (a document has been
  opened and it takes the place of an automatically-created window).  In that
  case this method is called twice.  First as #2 above, second as #1.

   The window can be visible or hidden at the time of the message.
*/
- (void)setDocument:(Document *)doc {
  Document *oldDoc = [self document];

  if (oldDoc) {
    [_layoutMgr unbind:@"hyphenationFactor"];
    [[self firstTextView] unbind:@"editable"];
  }
  [super setDocument:doc];
  if (doc) {
    [_layoutMgr bind:@"hyphenationFactor"
            toObject:self
         withKeyPath:@"document.hyphenationFactor"
             options:nil];
    [[self firstTextView]
               bind:@"editable"
           toObject:self
        withKeyPath:@"document.readOnly"
            options:[NSDictionary dictionaryWithObject:NSNegateBooleanTransformerName
                                                forKey:NSValueTransformerNameBindingOption]];
  }
  if (oldDoc != doc) {
    if (oldDoc) {
      /* Remove layout manager from the old Document's text storage. No need to
       * retain as we already own the object. */
      [[oldDoc textStorage] removeLayoutManager:_layoutMgr];

      [oldDoc removeObserver:self forKeyPath:@"printInfo"];
      [oldDoc removeObserver:self forKeyPath:@"richText"];
      [oldDoc removeObserver:self forKeyPath:@"hasMultiplePages"];
    }

    if (doc) {
      [[doc textStorage] addLayoutManager:_layoutMgr];

      if ([self isWindowLoaded]) {
        [self setHasMultiplePages:[doc hasMultiplePages]];
        [self setupInitialTextViewSharedState];
        [self setupWindowForDocument];
        [[doc undoManager] removeAllActions];
      }

      [doc addObserver:self forKeyPath:@"printInfo" options:0 context:NULL];
      [doc addObserver:self forKeyPath:@"richText" options:0 context:NULL];
      [doc addObserver:self forKeyPath:@"hasMultiplePages" options:0 context:NULL];
    }
  }
}

- (void)breakUndoCoalescing {
  [[self firstTextView] breakUndoCoalescing];
}

- (NSLayoutManager *)layoutManager {
  return _layoutMgr;
}

- (NSTextView *)firstTextView {
  return [[self layoutManager] firstTextView];
}

- (void)setupInitialTextViewSharedState {
  NSTextView *textView = [self firstTextView];

  [textView setUsesFontPanel:YES];
  [textView setUsesFindBar:YES];
  [textView setIncrementalSearchingEnabled:YES];
  [textView setDelegate:self];
  [textView setAllowsUndo:YES];
  [textView setAllowsDocumentBackgroundColorChange:YES];
  [textView setIdentifier:@"First Text View"];

  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

  // Some settings are not enabled for plain text docs if the default
  // "SubstitutionsEnabledInRichTextOnly" is set to YES. There is no UI at this
  // stage for this preference.
  BOOL substitutionsOK =
      [[self document] isRichText] || ![defaults boolForKey:SubstitutionsEnabledInRichTextOnly];
  [textView setContinuousSpellCheckingEnabled:[defaults boolForKey:CheckSpellingAsYouType]];
  [textView setGrammarCheckingEnabled:[defaults boolForKey:CheckGrammarWithSpelling]];
  [textView
      setAutomaticSpellingCorrectionEnabled:substitutionsOK &&
                                            [defaults boolForKey:CorrectSpellingAutomatically]];
  [textView setSmartInsertDeleteEnabled:[defaults boolForKey:SmartCopyPaste]];
  [textView
      setAutomaticQuoteSubstitutionEnabled:substitutionsOK && [defaults boolForKey:SmartQuotes]];
  [textView
      setAutomaticDashSubstitutionEnabled:substitutionsOK && [defaults boolForKey:SmartDashes]];
  [textView setAutomaticLinkDetectionEnabled:[defaults boolForKey:SmartLinks]];
  [textView setAutomaticDataDetectionEnabled:[defaults boolForKey:DataDetectors]];
  [textView
      setAutomaticTextReplacementEnabled:substitutionsOK && [defaults boolForKey:TextReplacement]];

  [textView setSelectedRange:NSMakeRange(0, 0)];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
  if (object == [self firstTextView]) {
    if ([keyPath isEqualToString:@"backgroundColor"]) {
      [[self document] setBackgroundColor:[[self firstTextView] backgroundColor]];
    }
  } else if (object == [self document]) {
    if ([keyPath isEqualToString:@"printInfo"]) {
      [self printInfoUpdated];
    } else if ([keyPath isEqualToString:@"hasMultiplePages"]) {
      [self setHasMultiplePages:[[self document] hasMultiplePages]];
    }
  }
}

- (void)setupTextViewForDocument {
  Document *doc = [self document];
  NSArray *sections = [doc originalOrientationSections];
  NSTextLayoutOrientation orientation = NSTextLayoutOrientationHorizontal;
  BOOL rich = [doc isRichText];

  if (doc && (!rich || [[[self firstTextView] textStorage] length] == 0)) {
    [[self firstTextView] setTypingAttributes:[doc defaultTextAttributes:rich]];
  }
  [self updateForRichTextAndRulerState:rich];

  [[self firstTextView] setBackgroundColor:[doc backgroundColor]];

  // process the initial container
  if ([sections count] > 0) {
    for (NSDictionary *dict in sections) {
      id rangeValue = [dict objectForKey:NSTextLayoutSectionRange];

      if (!rangeValue || NSLocationInRange(0, [rangeValue rangeValue])) {
        orientation = NSTextLayoutOrientationVertical;
        [[self firstTextView] setLayoutOrientation:orientation];
        break;
      }
    }
  }

  if (_hasMultiplePages && (orientation != NSTextLayoutOrientationHorizontal)) {
    [self setupPagesViewForLayoutOrientation:orientation];
  }
}

- (void)printInfoUpdated {
  if (_hasMultiplePages) {
    NSUInteger cnt;
    MultiplePageView *pagesView = [_scrollView documentView];
    NSArray *textContainers = [[self layoutManager] textContainers];

    [pagesView setPrintInfo:[[self document] printInfo]];

    for (cnt = 0; cnt < [self numberOfPages];
         cnt++) { // Call -numberOfPages repeatedly since it may change
      NSRect textFrame = [pagesView documentRectForPageNumber:cnt];
      NSTextContainer *textContainer = [textContainers objectAtIndex:cnt];
      [textContainer setContainerSize:textFrame.size];
      [[textContainer textView] setFrame:textFrame];
    }
  }
}

- (void)showRuler {
  if ([[NSUserDefaults standardUserDefaults] boolForKey:ShowRuler]) {
    [[self firstTextView] setRulerVisible:YES];
  }
}

/* Used when converting to plain text
 */
- (void)removeAttachments {
  NSTextStorage *attrString = [[self document] textStorage];
  NSTextView *view = [self firstTextView];
  NSUInteger loc = 0;
  NSUInteger end = [attrString length];
  [attrString beginEditing];
  while (loc < end) {        /* Run through the string in terms of attachment runs */
    NSRange attachmentRange; /* Attachment attribute run */
    NSTextAttachment *attachment = [attrString attribute:NSAttachmentAttributeName
                                                 atIndex:loc
                                   longestEffectiveRange:&attachmentRange
                                                 inRange:NSMakeRange(loc, end - loc)];
    if (attachment) { /* If there is an attachment and it is on an attachment
                         character, remove the character */
      unichar ch = [[attrString string] characterAtIndex:loc];
      if (ch == NSAttachmentCharacter) {
        if ([view shouldChangeTextInRange:NSMakeRange(loc, 1) replacementString:@""]) {
          [attrString replaceCharactersInRange:NSMakeRange(loc, 1) withString:@""];
          [view didChangeText];
        }
        end = [attrString length]; /* New length */
      } else {
        loc++; /* Just skip over the current character... */
      }
    } else {
      loc = NSMaxRange(attachmentRange);
    }
  }
  [attrString endEditing];
}

/* This method implements panel-based "attach" functionality. Note that as-is,
 * it's set to accept all files; however, by setting allowed types on the open
 * panel it can be restricted to images, etc.
 */

- (void)chooseAndAttachFiles:(id)sender {
  [[self document]
      performActivityWithSynchronousWaiting:YES
                                 usingBlock:^(void (^activityCompletionHandler)(void)) {
                                   NSOpenPanel *panel = [NSOpenPanel openPanel];
                                   [panel setCanChooseDirectories:YES];
                                   [panel setAllowsMultipleSelection:YES];
                                   // Use the 10.6-introduced
                                   // sheet API with block handler
                                   [panel
                                       beginSheetModalForWindow:[self window]
                                              completionHandler:^(NSInteger result) {
                                                if (result ==
                                                    NSModalResponseOK) { // Only if not cancelled
                                                  NSArray *urls = [panel URLs];
                                                  NSTextView *textView = [self firstTextView];
                                                  NSInteger numberOfErrors = 0;
                                                  NSError *error = nil;
                                                  NSMutableAttributedString *attachments =
                                                      [[NSMutableAttributedString alloc] init];

                                                  // Process
                                                  // all the
                                                  // attachments,
                                                  // creating
                                                  // an
                                                  // attributed
                                                  // string
                                                  for (NSURL *url in urls) {
                                                    NSFileWrapper *wrapper = [[NSFileWrapper alloc]
                                                        initWithURL:url
                                                            options:NSFileWrapperReadingImmediate
                                                              error:&error];
                                                    if (wrapper) {
                                                      NSTextAttachment *attachment =
                                                          [[NSTextAttachment alloc]
                                                              initWithFileWrapper:wrapper];
                                                      [attachments
                                                          appendAttributedString:
                                                              [NSAttributedString
                                                                  attributedStringWithAttachment:
                                                                      attachment]];
                                                    } else {
                                                      numberOfErrors++;
                                                    }
                                                  }

                                                  // We could
                                                  // actually
                                                  // take an
                                                  // approach
                                                  // where on
                                                  // partial
                                                  // success
                                                  // we allow
                                                  // the user
                                                  // to cancel
                                                  // the
                                                  // operation,
                                                  // but since
                                                  // it's easy
                                                  // enough to
                                                  // undo,
                                                  // this
                                                  // seems
                                                  // reasonable
                                                  // enough
                                                  if ([attachments length] > 0) {
                                                    NSRange selectionRange =
                                                        [textView selectedRange];
                                                    if ([textView
                                                            shouldChangeTextInRange:selectionRange
                                                                  replacementString:
                                                                      [attachments
                                                                          string]]) { // Shouldn't
                                                                                      // fail, since
                                                                                      // we are
                                                                                      // controlling
                                                                                      // the text
                                                                                      // view; but
                                                                                      // if it does,
                                                                                      // we simply
                                                                                      // don't allow
                                                                                      // the change
                                                      [[textView textStorage]
                                                          replaceCharactersInRange:selectionRange
                                                              withAttributedString:attachments];
                                                      [textView didChangeText];
                                                    }
                                                  }

                                                  [panel orderOut:nil]; // Strictly speaking not
                                                                        // necessary, but if we put
                                                                        // up an error sheet, a good
                                                                        // idea for the panel to be
                                                                        // dismissed first

                                                  // Deal with
                                                  // errors
                                                  // opening
                                                  // some or
                                                  // all of
                                                  // the
                                                  // attachments
                                                  if (numberOfErrors > 0) {
                                                    if (numberOfErrors >
                                                        1) { // More than one failure, put up a
                                                             // summary error (which doesn't do a
                                                             // good job of communicating the actual
                                                             // errors, but multiple attachments is
                                                             // a relatively rare case). For one
                                                             // error, we present the actual NSError
                                                             // we got back.
                                                      // The
                                                      // error
                                                      // message
                                                      // will
                                                      // be
                                                      // different
                                                      // depending
                                                      // on
                                                      // whether
                                                      // all
                                                      // or
                                                      // some
                                                      // of
                                                      // the
                                                      // files
                                                      // were
                                                      // successfully
                                                      // attached.
                                                      NSString *description =
                                                          (numberOfErrors == [urls count])
                                                              ? NSLocalizedString(
                                                                    @"None of the items could be "
                                                                    @"attached.",
                                                                    @"Title of alert indicating "
                                                                    @"error during 'Attach "
                                                                    @"Files...' when user tries to "
                                                                    @"attach (insert) multiple "
                                                                    @"files and none can be "
                                                                    @"attached.")
                                                              : NSLocalizedString(
                                                                    @"Some of the items could not "
                                                                    @"be attached.",
                                                                    @"Title of alert indicating "
                                                                    @"error during 'Attach "
                                                                    @"Files...' when user tries to "
                                                                    @"attach (insert) multiple "
                                                                    @"files and some fail.");
                                                      error = [NSError
                                                          errorWithDomain:TextEditErrorDomain
                                                                     code:TextEditAttachFilesFailure
                                                                 userInfo:
                                                                     [NSDictionary
                                                                         dictionaryWithObjectsAndKeys:
                                                                             description,
                                                                             NSLocalizedDescriptionKey,
                                                                             NSLocalizedString(
                                                                                 @"The files may "
                                                                                 @"be unreadable, "
                                                                                 @"or the volume "
                                                                                 @"they are on may "
                                                                                 @"be "
                                                                                 @"inaccessible. "
                                                                                 @"Please check in "
                                                                                 @"Finder.",
                                                                                 @"Recommendation "
                                                                                 @"when 'Attach "
                                                                                 @"Files...' "
                                                                                 @"command fails"),
                                                                             NSLocalizedRecoverySuggestionErrorKey,
                                                                             nil]];
                                                    }
                                                    NSAlert *alert = [NSAlert alertWithError:error];
                                                    [alert beginSheetModalForWindow:[self window]
                                                                  completionHandler:^(
                                                                      NSModalResponse returnCode) {
                                                                    activityCompletionHandler();
                                                                  }];
                                                  } else {
                                                    activityCompletionHandler();
                                                  }
                                                } else {
                                                  activityCompletionHandler();
                                                }
                                              }];
                                 }];
}

/* Doesn't check to see if the prev value is the same --- Otherwise the first
 * time doesn't work... */
- (void)updateForRichTextAndRulerState:(BOOL)rich {
  NSTextView *view = [self firstTextView];
  [view setRichText:rich];
  [view setUsesRuler:rich];
  [view setUsesInspectorBar:rich];
  if (rich && ![[self document] isReadOnly]) {
    [self showRuler];
  }
  [view setImportsGraphics:rich];
}

- (void)configureTypingAttributesAndDefaultParagraphStyleForTextView:(NSTextView *)view {
  Document *doc = [self document];
  BOOL rich = [doc isRichText];
  NSDictionary *textAttributes = [doc defaultTextAttributes:rich];
  NSParagraphStyle *paragraphStyle = [textAttributes objectForKey:NSParagraphStyleAttributeName];

  [view setTypingAttributes:textAttributes];
  [view setDefaultParagraphStyle:paragraphStyle];
}

- (void)convertTextForRichTextState:(BOOL)rich removeAttachments:(BOOL)attachmentFlag {
  NSTextView *view = [self firstTextView];
  Document *doc = [self document];
  NSDictionary *textAttributes = [doc defaultTextAttributes:rich];
  NSParagraphStyle *paragraphStyle = [textAttributes objectForKey:NSParagraphStyleAttributeName];

  // Note, since the textview content changes (removing attachments and changing
  // attributes) create undo actions inside the textview, we do not execute them
  // here if we're undoing or redoing
  if (![[doc undoManager] isUndoing] && ![[doc undoManager] isRedoing]) {
    NSTextStorage *textStorage = [[self document] textStorage];
    if (!rich && attachmentFlag) {
      [self removeAttachments];
    }
    NSRange range = NSMakeRange(0, [textStorage length]);
    if ([view shouldChangeTextInRange:range replacementString:nil]) {
      [textStorage beginEditing];
      [doc applyDefaultTextAttributes:rich];
      [textStorage endEditing];
      [view didChangeText];
    }
  }
  [view setTypingAttributes:textAttributes];
  [view setDefaultParagraphStyle:paragraphStyle];
}

- (NSUInteger)numberOfPages {
  return _hasMultiplePages ? [[_scrollView documentView] numberOfPages] : 1;
}

- (void)updateTextViewGeometry {
  MultiplePageView *pagesView = [_scrollView documentView];

  [[[self layoutManager] textContainers]
      enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        [[obj textView] setFrame:[pagesView documentRectForPageNumber:idx]];
      }];
}

- (void)setupPagesViewForLayoutOrientation:(NSTextLayoutOrientation)orientation {
  MultiplePageView *pagesView = [_scrollView documentView];

  [pagesView setLayoutOrientation:orientation];
  [[self firstTextView] setLayoutOrientation:orientation];
  [self updateTextViewGeometry];

  [_scrollView setHasHorizontalRuler:(NSTextLayoutOrientationHorizontal == orientation) ? YES : NO];
  [_scrollView setHasVerticalRuler:(NSTextLayoutOrientationHorizontal == orientation) ? NO : YES];
}

- (void)addPage {
  NSUInteger numberOfPages = [self numberOfPages];
  MultiplePageView *pagesView = [_scrollView documentView];

  NSSize textSize = [pagesView documentSizeInPage];
  NSTextContainer *textContainer = [[NSTextContainer alloc] initWithContainerSize:textSize];
  NSTextView *textView;
  NSUInteger orientation = [pagesView layoutOrientation];
  NSRect visibleRect = [pagesView visibleRect];
  CGFloat originalWidth = NSWidth([pagesView bounds]);

  [textContainer setWidthTracksTextView:YES];
  [textContainer setHeightTracksTextView:YES];

  [pagesView setNumberOfPages:numberOfPages + 1];
  if (NSTextLayoutOrientationVertical == [pagesView layoutOrientation]) {
    visibleRect.origin.x += (NSWidth([pagesView bounds]) - originalWidth);
    [pagesView scrollRectToVisible:visibleRect];
  }

  // Add container to the layout manager FIRST so that initWithFrame:textContainer:
  // finds sibling text views and inherits their NSTextViewSharedData (delegate,
  // ruler support, font panel, undo, spell checking, NSTextFinder, etc.).
  // This is critical under ARC: if each text view creates its own shared data,
  // the old shared data may be freed when pages are removed, crashing internal
  // AppKit code that still references it.
  //
  // Guard against the delegate's remove-page path: during addTextContainer:,
  // the layout manager may fire the delegate with "layout finished, all fit"
  // if the new container is empty (e.g., during the initial switch to multi-page
  // mode when the old single-page container still holds all the text).  Without
  // this guard, the delegate would immediately remove the page we're setting up.
  // The add-page path is NOT guarded, so the normal cascade works.
  _addingPageCount++;
  [[self layoutManager] addTextContainer:textContainer];

  // Create text view AFTER addTextContainer: — the container is in the layout
  // manager, so initWithFrame:textContainer: finds sibling text views and
  // shares their NSTextViewSharedData.
  textView = [[NSTextView alloc] initWithFrame:[pagesView documentRectForPageNumber:numberOfPages]
                                 textContainer:textContainer];

  [textView setHorizontallyResizable:NO];
  [textView setVerticallyResizable:NO];
  [textView setLayoutOrientation:orientation];

  if (NSTextLayoutOrientationVertical == orientation) {     // Adjust the initial container size
    textSize = NSMakeSize(textSize.height, textSize.width); // Translate size
    [textContainer setContainerSize:textSize];
  }

  [self configureTypingAttributesAndDefaultParagraphStyleForTextView:textView];
  [pagesView addSubview:textView];
  _addingPageCount--;
}

- (void)removePage {
  NSUInteger numberOfPages = [self numberOfPages];
  NSArray *textContainers = [[self layoutManager] textContainers];
  NSTextContainer *lastContainer = [textContainers objectAtIndex:[textContainers count] - 1];
  MultiplePageView *pagesView = [_scrollView documentView];

  // Keep a strong reference to the text view so it stays alive through the
  // removeTextContainerAtIndex: call.  That call triggers _fixSharedData /
  // resetStateForTextView: which accesses NSTextFinder's client (the text
  // view).  Without this, removeFromSuperview releases the last strong
  // reference and the text view is freed before the container removal.
  NSTextView *textView = [lastContainer textView];

  // If this text view is the window's first responder, resign it before
  // removal.  removeFromSuperview does not always clear the first responder
  // (especially on non-key windows), leaving a dangling pointer that
  // crashes when the window later becomes key and calls acquireKeyFocus.
  NSWindow *window = [textView window];
  if (window && [window firstResponder] == textView) {
    [window makeFirstResponder:[self firstTextView]];
  }

  [pagesView setNumberOfPages:numberOfPages - 1];
  [textView removeFromSuperview];
  [[lastContainer layoutManager] removeTextContainerAtIndex:[textContainers count] - 1];
}

- (NSView *)documentView {
  return [_scrollView documentView];
}

- (void)setHasMultiplePages:(BOOL)pages {
  NSTextLayoutOrientation orientation = NSTextLayoutOrientationHorizontal;

  if ([self firstTextView] && (_hasMultiplePages == pages)) {
    return;
  }

  // Keep the old first text view alive for the duration of this method.
  // The if/else blocks below replace the document view and remove old text
  // containers, which releases the old text view.
  NSTextView *oldFirstTextView = [self firstTextView];

  // Resign the current first responder while it's still alive and in the
  // view hierarchy.  In multi-page mode the first responder may be ANY
  // page's text view — not necessarily oldFirstTextView.  The if/else
  // blocks below replace the scroll view's document view, releasing old
  // text views.  makeFirstResponder: for the new text view doesn't happen
  // until the end of the method.  Without clearing now, the window holds
  // a dangling first responder that crashes in becomeKeyWindow →
  // acquireKeyFocus → objc_storeWeak.
  //
  // IMPORTANT: Do this BEFORE setting _hasMultiplePages.  resignFirstResponder
  // can trigger layout (e.g., committing IME input), which fires the layout
  // delegate.  If _hasMultiplePages were already the new value, the delegate
  // would try to add/remove pages with the wrong view hierarchy in place
  // (e.g., calling addPage when the document view is still a plain NSTextView).
  NSWindow *window = [_scrollView window];
  if (window) {
    [window makeFirstResponder:nil];
  }

  [oldFirstTextView removeObserver:self forKeyPath:@"backgroundColor"];
  [oldFirstTextView unbind:@"editable"];

  if (oldFirstTextView) {
    orientation = [oldFirstTextView layoutOrientation];
  } else {
    NSArray *sections = [[self document] originalOrientationSections];

    if (([sections count] > 0) &&
        (NSTextLayoutOrientationVertical ==
         [[[sections objectAtIndex:0] objectForKey:NSTextLayoutSectionOrientation]
             unsignedIntegerValue])) {
      orientation = NSTextLayoutOrientationVertical;
    }
  }

  // Set the flag AFTER all cleanup that might trigger layout callbacks.
  // The layout delegate checks _hasMultiplePages and calls addPage/removePage,
  // which assume the document view matches the flag.  Setting the flag while
  // the old view hierarchy is still in place would cause those calls to
  // operate on the wrong document view.
  _hasMultiplePages = pages;

  if (_hasMultiplePages) {
    MultiplePageView *pagesView = [[MultiplePageView alloc] init];

    [_scrollView setDocumentView:pagesView];

    [pagesView setPrintInfo:[[self document] printInfo]];
    [pagesView setLayoutOrientation:orientation];

    if (oldFirstTextView) {
      // Keep the existing text view (preserving NSTextViewSharedData) but
      // replace its container with a fresh one sized for the page.  Reusing
      // the old container causes the layout manager to retain stale layout
      // state from single-page mode; even explicit invalidation doesn't
      // fully clear it on subsequent round trips, so the page cascade fails.
      // replaceTextContainer: swaps the container in the layout manager
      // atomically — the text view is never disconnected, so _fixSharedData
      // always finds a valid owner and no crash occurs.
      NSSize textSize = [pagesView documentSizeInPage];
      if (NSTextLayoutOrientationVertical == orientation) {
        textSize = NSMakeSize(textSize.height, textSize.width);
      }

      NSTextContainer *freshContainer = [[NSTextContainer alloc] initWithContainerSize:textSize];
      [freshContainer setWidthTracksTextView:YES];
      [freshContainer setHeightTracksTextView:YES];

      [pagesView setNumberOfPages:1];
      [pagesView addSubview:oldFirstTextView];

      [oldFirstTextView setHorizontallyResizable:NO];
      [oldFirstTextView setVerticallyResizable:NO];
      [oldFirstTextView setFrame:[pagesView documentRectForPageNumber:0]];
      [oldFirstTextView setLayoutOrientation:orientation];

      [oldFirstTextView replaceTextContainer:freshContainer];

      [self configureTypingAttributesAndDefaultParagraphStyleForTextView:oldFirstTextView];
    } else {
      // First time setup (no existing text view) — create the first page.
      [self addPage];
    }

    if (NSTextLayoutOrientationVertical == orientation) {
      [self updateTextViewGeometry];
    }

    [[self firstTextView] scrollRangeToVisible:[[self firstTextView] selectedRange]];
  } else {
    NSSize size = [_scrollView contentSize];
    NSTextView *textView;
    NSTextContainer *textContainer;

    if ([[_scrollView documentView] isKindOfClass:[MultiplePageView class]]) {
      // Transitioning from multi-page: remove extra containers from the end.
      NSArray *containers = [[self layoutManager] textContainers];
      for (NSUInteger i = [containers count]; i > 1; i--) {
        NSTextView *pageView = [[containers objectAtIndex:i - 1] textView];
        [pageView removeFromSuperview];
        [[self layoutManager] removeTextContainerAtIndex:i - 1];
      }

      textView = [self firstTextView];
      textContainer =
          [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(size.width, CGFLOAT_MAX)];
      [textContainer setWidthTracksTextView:YES];
      [textContainer setHeightTracksTextView:NO];
      [textView replaceTextContainer:textContainer];
    } else {
      // Initial setup — create a new container and text view.
      textContainer =
          [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(size.width, CGFLOAT_MAX)];
      [[self layoutManager] addTextContainer:textContainer];
      textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)
                                     textContainer:textContainer];
    }

    [textView setHorizontallyResizable:NO];
    [textView setVerticallyResizable:YES];
    [textView setAutoresizingMask:NSViewWidthSizable];
    [textView setFrame:NSMakeRect(0, 0, size.width, size.height)];
    [textView setMinSize:size];
    [textView setMaxSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
    [self configureTypingAttributesAndDefaultParagraphStyleForTextView:textView];
    [textView setLayoutOrientation:orientation];

    [_scrollView setDocumentView:textView];
  }

  [_scrollView
      setHasHorizontalRuler:((orientation == NSTextLayoutOrientationHorizontal) ? YES : NO)];
  [_scrollView setHasVerticalRuler:((orientation == NSTextLayoutOrientationHorizontal) ? NO : YES)];

  // Re-establish per-view state on the first text view.  Because we repurpose
  // the existing text view (never destroy the "owner" in NSTextViewSharedData),
  // shared properties like delegate, usesFontPanel, allowsUndo, richText, etc.
  // are already intact.  We only need to set up the background color, observer,
  // binding, first responder, ruler visibility, and inspector bar.
  NSTextView *newFirstTextView = [self firstTextView];
  BOOL rich = [[self document] isRichText];

  [newFirstTextView setBackgroundColor:[[self document] backgroundColor]];

  if (rich && ![[self document] isReadOnly]) {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:ShowRuler]) {
      [newFirstTextView setRulerVisible:YES];
    }
  }

  [newFirstTextView addObserver:self forKeyPath:@"backgroundColor" options:0 context:NULL];
  [newFirstTextView bind:@"editable"
                toObject:self
             withKeyPath:@"document.readOnly"
                 options:[NSDictionary dictionaryWithObject:NSNegateBooleanTransformerName
                                                     forKey:NSValueTransformerNameBindingOption]];

  [[_scrollView window] makeFirstResponder:newFirstTextView];
  [[_scrollView window] setInitialFirstResponder:newFirstTextView]; // So focus won't be stolen
                                                                    // (2934918)

  // Set usesInspectorBar after the text view is first responder so the
  // inspector bar (formatting toolbar) properly attaches to the window for the
  // new text view.
  [newFirstTextView setUsesInspectorBar:rich];

  // If entering multi-page mode, force the page cascade to complete now.
  // Invalidate all layout first: the container was resized from CGFLOAT_MAX
  // to page height, but the layout manager may not have fully invalidated
  // (e.g., if tracking modes interfered with setContainerSize:, or if
  // layout callbacks were deferred during a display cycle).
  if (_hasMultiplePages) {
    NSLayoutManager *lm = [self layoutManager];
    NSUInteger len = [[lm textStorage] length];
    if (len > 0) {
      [lm invalidateLayoutForCharacterRange:NSMakeRange(0, len) actualCharacterRange:NULL];
    }
    [self _syncPages];
  }
}

- (void)setupWindowForDocument {
  [self setupTextViewForDocument];
}

- (void)windowDidLoad {
  [super windowDidLoad];

  // Force Auto Layout to resolve the scroll view's frame before creating
  // the text view.  Without this, contentSize and ruler tiling use a stale
  // frame because constraints haven't been evaluated yet.
  [[_scrollView superview] layoutSubtreeIfNeeded];

  // This creates the first text view
  [self setHasMultiplePages:[[self document] hasMultiplePages]];

  // This sets it up
  [self setupInitialTextViewSharedState];

  // This makes sure the window's UI (including text view shared state) is
  // updated to reflect the document
  [self setupWindowForDocument];

  [[[self document] undoManager] removeAllActions];
}

- (void)setDocumentEdited:(BOOL)edited {
  [super setDocumentEdited:edited];
  if (edited) {
    [[self document] setOriginalOrientationSections:nil];
  }
}

/* Layout orientation sections */
- (NSArray *)layoutOrientationSections {
  NSArray *textContainers = [_layoutMgr textContainers];
  NSMutableArray *sections = nil;
  NSUInteger layoutOrientation = 0; // horizontal
  NSRange range = NSMakeRange(0, 0);

  for (NSTextContainer *container in textContainers) {
    NSUInteger newOrientation = [container layoutOrientation];

    if (newOrientation != layoutOrientation) {
      if (range.length > 0) {
        if (!sections) {
          sections = [NSMutableArray arrayWithCapacity:0];
        }

        [sections
            addObject:[NSDictionary
                          dictionaryWithObjectsAndKeys:[NSNumber
                                                           numberWithInteger:layoutOrientation],
                                                       NSTextLayoutSectionOrientation,
                                                       [NSValue valueWithRange:range],
                                                       NSTextLayoutSectionRange, nil]];

        range.length = 0;
      }

      layoutOrientation = newOrientation;
    }

    if (layoutOrientation > 0) {
      NSRange containerRange =
          [_layoutMgr characterRangeForGlyphRange:[_layoutMgr glyphRangeForTextContainer:container]
                                 actualGlyphRange:NULL];

      if (range.length == 0) {
        range = containerRange;
      } else {
        range.length = NSMaxRange(containerRange) - range.location;
      }
    }
  }

  if (range.length > 0) {
    if (!sections) {
      sections = [NSMutableArray arrayWithCapacity:0];
    }

    [sections
        addObject:[NSDictionary
                      dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:layoutOrientation],
                                                   NSTextLayoutSectionOrientation,
                                                   [NSValue valueWithRange:range],
                                                   NSTextLayoutSectionRange, nil]];
  }

  return sections;
}

- (void)toggleRichWithNewFileType:(NSString *)type {
  Document *document = [self document];
  NSURL *fileURL = [document fileURL];
  BOOL isRich = [document isRichText]; // This is the old value

  NSUndoManager *undoManager = [document undoManager];
  [undoManager beginUndoGrouping];

  NSString *undoType = (isRich) ? (([[[self firstTextView] textStorage] containsAttachments] ||
                                    [[document fileType] isEqualToString:UTTypeRTFD.identifier])
                                       ? UTTypeRTFD.identifier
                                       : UTTypeRTF.identifier)
                                : UTTypePlainText.identifier;

  [undoManager registerUndoWithTarget:self selector:_cmd object:undoType];

  [document setUsesScreenFonts:isRich];
  [self updateForRichTextAndRulerState:!isRich];
  [self convertTextForRichTextState:!isRich removeAttachments:isRich];

  if (isRich) {
    [document clearDocumentProperties];
  } else {
    [document setDocumentPropertiesToDefaults];
  }

  [undoManager setActionName:([undoManager isUndoing] ^ isRich)
                                 ? NSLocalizedString(@"Make Plain Text",
                                                     @"Undo menu item text (without 'Undo ') "
                                                     @"for making a document plain text")
                                 : NSLocalizedString(@"Make Rich Text",
                                                     @"Undo menu item text (without 'Undo ') "
                                                     @"for making a document rich text")];

  [undoManager endUndoGrouping];

  if (type == nil) {
    type = isRich ? UTTypePlainText.identifier : UTTypeRTF.identifier;
  }

  if (fileURL) {
    [document saveToURL:fileURL
                   ofType:type
         forSaveOperation:NSAutosaveInPlaceOperation
        completionHandler:^(NSError *error) {
          if (error) {
            [document setFileURL:nil];
            [document setFileType:type];
          }
        }];
  } else {
    [document setFileType:type];
  }
}

- (void)autosaveIfNeededThenToggleRich {
  Document *document = [self document];

  if ([document fileURL] && [document isDocumentEdited]) {
    [document autosaveWithImplicitCancellability:NO
                               completionHandler:^(NSError *error) {
                                 if (!error) {
                                   [self toggleRichWithNewFileType:nil];
                                 }
                               }];
  } else {
    [self toggleRichWithNewFileType:nil];
  }
}

/* toggleRich: puts up an alert before ultimately calling -setRichText:
 */
- (void)toggleRich:(id)sender {
  Document *document = [self document];
  // Check if there is any loss of information
  if ([document toggleRichWillLoseInformation]) {
    [document
        performActivityWithSynchronousWaiting:YES
                                   usingBlock:^(void (^activityCompletionHandler)(void)) {
                                     NSAlert *alert = [[NSAlert alloc] init];
                                     [alert setMessageText:NSLocalizedString(
                                                               @"Convert this document to "
                                                               @"plain text?",
                                                               @"Title of alert confirming "
                                                               @"Make Plain Text")];
                                     [alert setInformativeText:NSLocalizedString(
                                                                   @"Making a rich text "
                                                                   @"document plain will lose "
                                                                   @"all text styles (such as "
                                                                   @"fonts and colors), "
                                                                   @"images, attachments, and "
                                                                   @"document properties.",
                                                                   @"Subtitle of alert "
                                                                   @"confirming Make Plain "
                                                                   @"Text")];
                                     [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK")];
                                     [alert addButtonWithTitle:NSLocalizedString(
                                                                   @"Cancel",
                                                                   @"Button choice that allows "
                                                                   @"the user to cancel.")];
                                     [alert
                                         beginSheetModalForWindow:[[self document] windowForSheet]
                                                completionHandler:^(NSModalResponse returnCode) {
                                                  if (returnCode == NSAlertFirstButtonReturn) {
                                                    [self autosaveIfNeededThenToggleRich];
                                                  }
                                                  activityCompletionHandler();
                                                }];
                                   }];
  } else {
    [self autosaveIfNeededThenToggleRich];
  }
}

/* Layout orientation
 */
- (void)toggleLayoutOrientation:(id)sender {
  NSInteger tag = [sender tag];

  if (_hasMultiplePages) {
    NSUInteger count = [[[self layoutManager] textContainers] count];

    while (count-- > 1) {
      [self removePage]; // remove 2nd ~ nth pages
    }

    [self setupPagesViewForLayoutOrientation:tag];
  } else {
    [[self firstTextView] setLayoutOrientation:[sender tag]];
  }
}
@end

@implementation DocumentWindowController (Delegation)

/* Window delegation messages */

- (NSRect)windowWillUseStandardFrame:(NSWindow *)window defaultFrame:(NSRect)defaultFrame {
  return defaultFrame;
}

- (void)windowDidResize:(NSNotification *)notification {
  [[self document] setTransient:NO]; // Since the user has taken an interest in the window,
                                     // clear the document's transient status
}

- (void)windowDidMove:(NSNotification *)notification {
  [[self document] setTransient:NO]; // Since the user has taken an interest in the window,
                                     // clear the document's transient status
}

/* Text view delegation messages */

- (BOOL)textView:(NSTextView *)textView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex {
  NSURL *linkURL = nil;

  if ([link isKindOfClass:[NSURL class]]) { // Handle NSURL links
    linkURL = link;
  } else if ([link isKindOfClass:[NSString class]]) { // Handle NSString links
    linkURL = [NSURL URLWithString:link relativeToURL:[[self document] fileURL]];
  }
  if (linkURL) {
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    if ([linkURL isFileURL]) {
      NSError *error = nil;
      if (![linkURL checkResourceIsReachableAndReturnError:&error]) { // To be able to present an
                                                                      // error panel, see if the
                                                                      // file is reachable
        [[self document]
            performActivityWithSynchronousWaiting:YES
                                       usingBlock:^(void (^activityCompletionHandler)(void)) {
                                         NSAlert *alert = [NSAlert alertWithError:error];
                                         [alert beginSheetModalForWindow:[self window]
                                                       completionHandler:^(
                                                           NSModalResponse returnCode) {
                                                         activityCompletionHandler();
                                                       }];
                                       }];
        return YES;
      } else {
        // Special case: We want to open text types in TextEdit, as presumably
        // that is what was desired
        UTType *contentType = nil;
        if ([linkURL getResourceValue:&contentType forKey:NSURLContentTypeKey error:NULL] &&
            contentType) {
          NSString *typeIdentifier = contentType.identifier;
          BOOL openInTextEdit = NO;
          for (NSString *textTypeIdentifier in [NSAttributedString textTypes]) {
            if ([[UTType typeWithIdentifier:typeIdentifier]
                    conformsToType:[UTType typeWithIdentifier:textTypeIdentifier]]) {
              openInTextEdit = YES;
              break;
            }
          }
          if (openInTextEdit) {
            [[NSDocumentController sharedDocumentController]
                openDocumentWithContentsOfURL:linkURL
                                      display:YES
                            completionHandler:^(NSDocument *document, BOOL documentWasAlreadyOpen,
                                                NSError *error) {
                              if (!document && error) {
                                NSAlert *alert = [NSAlert alertWithError:error];
                                [alert runModal];
                              }
                            }];
            return YES;
          }
        }
        // Other file URLs are displayed in Finder
        [workspace activateFileViewerSelectingURLs:[NSArray arrayWithObject:linkURL]];
        return YES;
      }
    } else {
      // Other URLs are simply opened
      if ([workspace openURL:linkURL]) {
        return YES;
      }
    }
  }

  // We only get here on failure... Because we beep, we return YES to indicate
  // "success", so the text system does no further processing.
  NSBeep();
  return YES;
}

- (NSURL *)textView:(NSTextView *)textView
    URLForContentsOfTextAttachment:(NSTextAttachment *)textAttachment
                           atIndex:(NSUInteger)charIndex {
  NSURL *attachmentURL = nil;
  NSString *name = [[textAttachment fileWrapper] filename];

  if (name) {
    Document *document = [self document];
    NSURL *docURL = [document fileURL];

    if (!docURL) {
      docURL = [document autosavedContentsFileURL];
    }

    if (docURL && [docURL isFileURL]) {
      attachmentURL = [docURL URLByAppendingPathComponent:name];
    }
  }

  return attachmentURL;
}

- (NSArray *)textView:(NSTextView *)view
    writablePasteboardTypesForCell:(id<NSTextAttachmentCell>)cell
                           atIndex:(NSUInteger)charIndex {
  NSString *name = [[[cell attachment] fileWrapper] filename];
  NSURL *docURL = [[self document] fileURL];
  return (docURL && [docURL isFileURL] && name) ? [NSArray arrayWithObject:NSPasteboardTypeFileURL]
                                                : nil;
}

- (BOOL)textView:(NSTextView *)view
       writeCell:(id<NSTextAttachmentCell>)cell
         atIndex:(NSUInteger)charIndex
    toPasteboard:(NSPasteboard *)pboard
            type:(NSString *)type {
  NSString *name = [[[cell attachment] fileWrapper] filename];
  NSURL *docURL = [[self document] fileURL];
  if ([type isEqualToString:NSPasteboardTypeFileURL] && name && [docURL isFileURL]) {
    NSURL *attachmentURL = [docURL URLByAppendingPathComponent:name];
    if (attachmentURL) {
      [pboard writeObjects:@[ attachmentURL ]];
      return YES;
    }
  }
  return NO;
}

/* Layout manager delegation message.  Adding/removing pages modifies the view
 * hierarchy (addSubview/removeFromSuperview).  When this callback fires during
 * a display cycle (layout triggered by drawRect:), modifying the view hierarchy
 * throws an exception.  Detect this situation and defer page changes until the
 * display cycle completes.
 */

- (void)layoutManager:(NSLayoutManager *)layoutManager
    didCompleteLayoutForTextContainer:(NSTextContainer *)textContainer
                                atEnd:(BOOL)layoutFinishedFlag {
  if (!_hasMultiplePages) {
    return;
  }

  // If called during a view display cycle, defer page changes.
  // performSelector:afterDelay:0 is self-coalescing with
  // cancelPreviousPerformRequests, so no flag is needed.
  if ([NSGraphicsContext currentContext]) {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(_syncPages)
                                               object:nil];
    [self performSelector:@selector(_syncPages) withObject:nil afterDelay:0];
    return;
  }

  [self _handleLayoutForContainer:textContainer
                            atEnd:layoutFinishedFlag
                    layoutManager:layoutManager];
}

/* Deferred page sync — called after a display cycle that needed page changes. */
- (void)_syncPages {
  if (!_hasMultiplePages) {
    return;
  }
  NSLayoutManager *lm = [self layoutManager];
  NSArray *containers = [lm textContainers];
  if ([containers count] == 0) {
    return;
  }

  // Force layout completion.  Each ensureLayoutForTextContainer: may add one
  // page (via the delegate cascade), so keep going until no new pages appear.
  NSUInteger previousCount = 0;
  while ([containers count] != previousCount) {
    previousCount = [containers count];
    [lm ensureLayoutForTextContainer:[containers lastObject]];
    containers = [lm textContainers];
  }

  // Remove excess empty trailing pages.
  NSUInteger count = [containers count];
  while (count > 1) {
    NSTextContainer *last = [containers objectAtIndex:count - 1];
    if ([lm glyphRangeForTextContainer:last].length == 0) {
      [self removePage];
      count--;
      containers = [lm textContainers];
    } else {
      break;
    }
  }

  MultiplePageView *pagesView = [_scrollView documentView];
  if ([pagesView isKindOfClass:[MultiplePageView class]] &&
      NSTextLayoutOrientationVertical == [pagesView layoutOrientation]) {
    [self updateTextViewGeometry];
  }
  [[self document] setOriginalOrientationSections:nil];
}

/* Core page-add/remove logic, called from the layout delegate callback when
 * not inside a display cycle.
 */
- (void)_handleLayoutForContainer:(NSTextContainer *)textContainer
                            atEnd:(BOOL)layoutFinishedFlag
                    layoutManager:(NSLayoutManager *)layoutManager {
  MultiplePageView *pagesView = [_scrollView documentView];
  NSArray *containers = [layoutManager textContainers];

  if (!layoutFinishedFlag || (textContainer == nil)) {
    // Either layout is not finished or it is but there are glyphs laid
    // nowhere.
    NSTextContainer *lastContainer = [containers lastObject];

    if ((textContainer == lastContainer) || (textContainer == nil)) {
      // Add a new page if the newly full container is the last container or
      // the nowhere container. Do this only if there are glyphs laid in the
      // last container (temporary solution for 3729692, until AppKit makes
      // something better available.)
      if ([layoutManager glyphRangeForTextContainer:lastContainer].length > 0) {
        [self addPage];
        if (NSTextLayoutOrientationVertical == [pagesView layoutOrientation]) {
          [self updateTextViewGeometry];
        }
      }
    }
  } else {
    // Layout is done and it all fit.  See if we can axe some pages.
    // Skip page removal if we are inside addPage's addTextContainer: call.
    // During addTextContainer:, the layout manager may fire this callback
    // reporting "all fit" while the new container is still empty (e.g.,
    // during the initial switch to multi-page mode when the old single-page
    // container still holds all the text).  Removing the new container here
    // would destroy the page that addPage is setting up.  Excess pages will
    // be cleaned up by subsequent layout passes or _syncPages.
    if (_addingPageCount > 0) {
      return;
    }

    NSUInteger lastUsedContainerIndex = [containers indexOfObjectIdenticalTo:textContainer];
    NSUInteger numContainers = [containers count];

    // Collect strong references to the text views that will be removed.
    // This callback can fire re-entrantly during event handling (e.g.,
    // menuForEvent: triggers layout, which removes pages while a text view
    // is still processing the right-click event). Without keeping the text
    // views alive, the calling text view's self pointer becomes dangling and
    // ARC crashes trying to retain it in the delegate method.
    NSMutableArray *removedTextViews = nil;
    if (lastUsedContainerIndex + 1 < numContainers) {
      removedTextViews = [NSMutableArray array];
      for (NSUInteger i = lastUsedContainerIndex + 1; i < numContainers; i++) {
        NSTextView *tv = [[containers objectAtIndex:i] textView];
        if (tv) {
          [removedTextViews addObject:tv];
        }
      }
    }

    while (++lastUsedContainerIndex < numContainers) {
      [self removePage];
    }

    // Defer release of removed text views until after the current event
    // finishes processing, so any text view still on the call stack (e.g.,
    // inside menuForEvent:) remains valid.
    if ([removedTextViews count] > 0) {
      dispatch_async(dispatch_get_main_queue(), ^{
        (void)removedTextViews;
      });
    }

    if (NSTextLayoutOrientationVertical == [pagesView layoutOrientation]) {
      [self updateTextViewGeometry];
    }

    [[self document] setOriginalOrientationSections:nil];
  }
}

@end

@implementation DocumentWindowController (NSMenuValidation)

- (BOOL)validateMenuItem:(NSMenuItem *)aCell {
  SEL action = [aCell action];
  if (action == @selector(toggleRich:)) {
    validateToggleItem(
        aCell, [[self document] isRichText],
        NSLocalizedString(@"&Make Plain Text",
                          @"Menu item to make the current document plain text"),
        NSLocalizedString(@"&Make Rich Text", @"Menu item to make the current document rich text"));
    if ([[self document] isReadOnly]) {
      return NO;
    }
  } else if (action == @selector(chooseAndAttachFiles:)) {
    return [[self document] isRichText] && ![[self document] isReadOnly];
  } else if (action == @selector(toggleLayoutOrientation:)) {
    NSString *title = nil;
    NSTextLayoutOrientation orientation = [[self firstTextView] layoutOrientation];
    ;

    if (NSTextLayoutOrientationHorizontal == orientation) {
      title = NSLocalizedString(@"Make Layout Vertical",
                                @"Menu item ot make the current document layout vertical");
      orientation = NSTextLayoutOrientationVertical;
    } else {
      title = NSLocalizedString(@"Make Layout Horizontal",
                                @"Menu item ot make the current document layout horizontal");
      orientation = NSTextLayoutOrientationHorizontal;
    }

    [aCell setTitle:title];
    [aCell setTag:orientation];

    if ([[self document] isReadOnly]) {
      return NO;
    }
  }
  return YES;
}

- (NSMenu *)textView:(NSTextView *)view
                menu:(NSMenu *)menu
            forEvent:(NSEvent *)event
             atIndex:(NSUInteger)charIndex {
  // Removing layout orientation menu item in multipage mode for enforcing the
  // document-wide setting
  if (_hasMultiplePages) {
    [[menu itemArray] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
      BOOL remove = NO;
      if ([obj action] == @selector(changeLayoutOrientation:)) {
        remove = YES;
      } else {
        NSMenu *submenu = [obj submenu];

        if (submenu) {
          [[submenu itemArray] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            if ([obj action] == @selector(changeLayoutOrientation:)) {
              [submenu removeItem:obj];
            }
          }];
          if (0 == [submenu numberOfItems]) {
            remove = YES;
          }
        }
      }

      if (remove) {
        [menu removeItem:obj];
        *stop = YES;
      }
    }];
  }
  return menu;
}
@end

@implementation NSTextView (TextEditAdditions)

/* This method causes the text to be laid out in the foreground (approximately)
 * up to the indicated character index.  Note that since we are adding a
 * category on a system framework, we are prefixing the method with "textEdit"
 * to greatly reduce chance of any naming conflict.
 */
- (void)textEditDoForegroundLayoutToCharacterIndex:(NSUInteger)loc {
  NSUInteger len;
  if (loc > 0 && (len = [[self textStorage] length]) > 0) {
    NSRange glyphRange;
    if (loc >= len) {
      loc = len - 1;
    }
    /* Find out which glyph index the desired character index corresponds to */
    glyphRange = [[self layoutManager] glyphRangeForCharacterRange:NSMakeRange(loc, 1)
                                              actualCharacterRange:NULL];
    if (glyphRange.location > 0) {
      /* Now cause layout by asking a question which has to determine where the
       * glyph is */
      (void)[[self layoutManager] textContainerForGlyphAtIndex:glyphRange.location - 1
                                                effectiveRange:NULL];
    }
  }
}

@end
