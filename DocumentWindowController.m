
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

@interface DocumentWindowController ()
@property(nonatomic, strong) IBOutlet ScalingScrollView *scrollView;
@property(nonatomic, strong) NSLayoutManager *layoutMgr;
@property(nonatomic, assign) BOOL hasMultiplePages;
@property(nonatomic, assign) BOOL rulerIsBeingDisplayed;
@property(nonatomic, assign) BOOL isSettingSize;
@property(nonatomic, assign) BOOL pageUpdateDeferred;
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

- (void)showRulerDelayed:(BOOL)flag;

- (void)addPage;
- (void)removePage;
- (void)_syncPages;
- (void)_handleLayoutForContainer:(NSTextContainer *)textContainer
                            atEnd:(BOOL)layoutFinishedFlag
                    layoutManager:(NSLayoutManager *)layoutManager;

- (NSTextView *)firstTextView;

- (void)printInfoUpdated;

- (void)resizeWindowForViewSize:(NSSize)size;
- (void)setHasMultiplePages:(BOOL)pages force:(BOOL)force;

@end

@implementation DocumentWindowController

- (id)init {
  if (self = [super initWithWindowNibName:@"DocumentWindow"]) {
    _layoutMgr = [[NSLayoutManager alloc] init];
    [_layoutMgr setDelegate:self];
    [_layoutMgr setAllowsNonContiguousLayout:YES];
  }
  return self;
}

- (void)dealloc {
  if ([self document]) {
    [self setDocument:nil];
  }

  [[NSNotificationCenter defaultCenter] removeObserver:self];

  [[self firstTextView] removeObserver:self forKeyPath:@"backgroundColor"];
  [_scrollView removeObserver:self forKeyPath:@"scaleFactor"];
  [[_scrollView verticalScroller] removeObserver:self forKeyPath:@"scrollerStyle"];

  [self showRulerDelayed:NO];
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
      [oldDoc removeObserver:self forKeyPath:@"viewSize"];
      [oldDoc removeObserver:self forKeyPath:@"hasMultiplePages"];
    }

    if (doc) {
      [[doc textStorage] addLayoutManager:_layoutMgr];

      if ([self isWindowLoaded]) {
        [self setHasMultiplePages:[doc hasMultiplePages] force:NO];
        [self setupInitialTextViewSharedState];
        [self setupWindowForDocument];
        if ([doc hasMultiplePages]) {
          [_scrollView setScaleFactor:[[self document] scaleFactor] adjustPopup:YES];
        }
        [[doc undoManager] removeAllActions];
      }

      [doc addObserver:self forKeyPath:@"printInfo" options:0 context:NULL];
      [doc addObserver:self forKeyPath:@"richText" options:0 context:NULL];
      [doc addObserver:self forKeyPath:@"viewSize" options:0 context:NULL];
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
  } else if (object == _scrollView) {
    if ([keyPath isEqualToString:@"scaleFactor"]) {
      [[self document] setScaleFactor:[_scrollView scaleFactor]];
    }
  } else if (object == [_scrollView verticalScroller]) {
    if ([keyPath isEqualToString:@"scrollerStyle"]) {
      [self invalidateRestorableState];
      NSSize size = [[self document] viewSize];
      if (!NSEqualSizes(size, NSZeroSize)) {
        [self resizeWindowForViewSize:size];
      }
    }
  } else if (object == [self document]) {
    if ([keyPath isEqualToString:@"printInfo"]) {
      [self printInfoUpdated];
    } else if ([keyPath isEqualToString:@"viewSize"]) {
      if (!_isSettingSize) {
        NSSize size = [[self document] viewSize];
        if (!NSEqualSizes(size, NSZeroSize)) {
          [self resizeWindowForViewSize:size];
        }
      }
    } else if ([keyPath isEqualToString:@"hasMultiplePages"]) {
      [self setHasMultiplePages:[[self document] hasMultiplePages] force:NO];
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

/* Method to lazily display ruler. Call with YES to display, NO to cancel
 * display; this method doesn't remove the ruler.
 */
- (void)showRulerDelayed:(BOOL)flag {
  if (!flag && _rulerIsBeingDisplayed) {
    [[self class] cancelPreviousPerformRequestsWithTarget:self
                                                 selector:@selector(showRuler:)
                                                   object:self];
  } else if (flag && !_rulerIsBeingDisplayed) {
    [self performSelector:@selector(showRuler:) withObject:self afterDelay:0.0];
  }
  _rulerIsBeingDisplayed = flag;
}

- (void)showRuler:(id)obj {
  if (_rulerIsBeingDisplayed && !obj) {
    [self showRulerDelayed:NO]; // Cancel outstanding request, if not coming
                                // from the delayed request
  }
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
  [view setUsesRuler:rich]; // If NO, this correctly gets rid of the ruler if it
                            // was up
  [view setUsesInspectorBar:rich];
  if (!rich && _rulerIsBeingDisplayed) {
    [self showRulerDelayed:NO]; // Cancel delayed ruler request
  }
  if (rich && ![[self document] isReadOnly]) {
    [self showRulerDelayed:YES];
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

- (void)setHasMultiplePages:(BOOL)pages force:(BOOL)force {
  NSTextLayoutOrientation orientation = NSTextLayoutOrientationHorizontal;

  if (!force && (_hasMultiplePages == pages)) {
    return;
  }

  _hasMultiplePages = pages;

  // Keep the old first text view alive for the duration of this method.
  // The if/else blocks below replace the document view and remove old text
  // containers, which releases the old text view.  But makeFirstResponder:
  // for the new text view doesn't happen until the end of the method.  If
  // the old text view is freed before then, the window holds a dangling
  // first responder pointer that crashes in becomeKeyWindow → acquireKeyFocus
  // (e.g., when the menu returns key status to the window).
  NSTextView *oldFirstTextView = [self firstTextView];

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

  if (_hasMultiplePages) {
    MultiplePageView *pagesView = [[MultiplePageView alloc] init];

    [_scrollView setDocumentView:pagesView];

    [pagesView setPrintInfo:[[self document] printInfo]];
    [pagesView setLayoutOrientation:orientation];

    // Add the first new page before we remove the old container so we can avoid
    // losing all the shared text view state.
    [self addPage];
    if (oldFirstTextView) {
      [[self layoutManager] removeTextContainerAtIndex:0];
    }

    if (NSTextLayoutOrientationVertical == orientation) {
      [self updateTextViewGeometry];
    }

    [_scrollView setHasVerticalScroller:YES];
    [_scrollView setHasHorizontalScroller:YES];

    // Make sure the selected text is shown
    [[self firstTextView] scrollRangeToVisible:[[self firstTextView] selectedRange]];

    NSRect visRect = [pagesView visibleRect];
    NSRect pageRect = [pagesView pageRectForPageNumber:0];
    if (visRect.size.width <
        pageRect.size.width) { // If we can't show the whole page, tweak a little further
      NSRect docRect = [pagesView documentRectForPageNumber:0];
      if (visRect.size.width >= docRect.size.width) { // Center document area in window
        visRect.origin.x = docRect.origin.x - floor((visRect.size.width - docRect.size.width) / 2);
        if (visRect.origin.x < pageRect.origin.x) {
          visRect.origin.x = pageRect.origin.x;
        }
      } else { // If we can't show the document area, then show left edge of
               // document area (w/out margins)
        visRect.origin.x = docRect.origin.x;
      }
      [pagesView scrollRectToVisible:visRect];
    }
  } else {
    NSSize size = [_scrollView contentSize];
    NSTextContainer *textContainer =
        [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(size.width, CGFLOAT_MAX)];

    // Insert the container into the layout manager BEFORE creating the text
    // view, so initWithFrame:textContainer: properly connects to the text
    // system and inherits NSTextViewSharedData from sibling text views.
    [[self layoutManager] insertTextContainer:textContainer atIndex:0];

    // Create the text view while the old page containers are still in the
    // layout manager.  This way initWithFrame:textContainer: finds siblings
    // and inherits their NSTextViewSharedData.  If we removed old containers
    // first, _fixSharedData during removal would update shared data to
    // reference old text views that are about to be freed, corrupting the
    // shared state for subsequent text views.
    NSTextView *textView =
        [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, size.width, size.height)
                            textContainer:textContainer];

    if ([[_scrollView documentView] isKindOfClass:[MultiplePageView class]]) {
      NSArray *textContainers = [[self layoutManager] textContainers];
      NSUInteger cnt = [textContainers count];
      while (cnt-- > 1) {
        [[self layoutManager] removeTextContainerAtIndex:cnt];
      }
    }

    [textContainer setWidthTracksTextView:YES];
    [textContainer setHeightTracksTextView:NO]; /* Not really necessary */
    [textView setHorizontallyResizable:NO];     /* Not really necessary */
    [textView setVerticallyResizable:YES];
    [textView setAutoresizingMask:NSViewWidthSizable];
    [textView setMinSize:size]; /* Not really necessary; will be adjusted by the
                                   autoresizing... */
    [textView setMaxSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)]; /* Will be adjusted by the
                                                                   autoresizing... */
    [self configureTypingAttributesAndDefaultParagraphStyleForTextView:textView];

    [textView setLayoutOrientation:orientation]; // this configures the above settings

    /* The next line should cause the multiple page view and everything else to
     * go away */
    [_scrollView setDocumentView:textView];

    [_scrollView setHasVerticalScroller:YES];
    [_scrollView setHasHorizontalScroller:YES];

    // Show the selected region
    [[self firstTextView] scrollRangeToVisible:[[self firstTextView] selectedRange]];
  }

  [_scrollView
      setHasHorizontalRuler:((orientation == NSTextLayoutOrientationHorizontal) ? YES : NO)];
  [_scrollView setHasVerticalRuler:((orientation == NSTextLayoutOrientationHorizontal) ? NO : YES)];

  // Re-establish shared state on the new first text view.  The text view
  // inherits NSTextViewSharedData from its siblings during addPage, but some
  // properties (binding, observer, inspector bar) must be set up here after
  // the transition completes.  The other setters are belt-and-suspenders to
  // ensure the delegate, font panel, undo, and rich-text state are correct.
  NSTextView *newFirstTextView = [self firstTextView];
  BOOL rich = [[self document] isRichText];
  [newFirstTextView setDelegate:self];
  [newFirstTextView setUsesFontPanel:YES];
  [newFirstTextView setUsesFindBar:YES];
  [newFirstTextView setIncrementalSearchingEnabled:YES];
  [newFirstTextView setAllowsUndo:YES];
  [newFirstTextView setAllowsDocumentBackgroundColorChange:YES];
  [newFirstTextView setBackgroundColor:[[self document] backgroundColor]];
  [newFirstTextView setRichText:rich];
  [newFirstTextView setUsesRuler:rich];
  [newFirstTextView setImportsGraphics:rich];
  if (rich && ![[self document] isReadOnly]) {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:ShowRuler]) {
      [newFirstTextView setRulerVisible:YES];
    }
    _rulerIsBeingDisplayed = YES;
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
}

/* We override these pair of methods so we can stash away the scrollerStyle,
 * since we want to preserve the size of the document (rather than the size of
 * the window).
 */
- (void)restoreStateWithCoder:(NSCoder *)coder {
  [super restoreStateWithCoder:coder];
  if ([coder containsValueForKey:@"scrollerStyle"]) {
    NSScrollerStyle previousScrollerStyle = [coder decodeIntegerForKey:@"scrollerStyle"];
    if (previousScrollerStyle != [NSScroller preferredScrollerStyle] &&
        ![[self document] hasMultiplePages]) {
      // When we encoded the frame, the window was sized for this saved style.
      // The preferred scroller style has since changed. Given our current frame
      // and the style it had applied, compute how big the view must have been,
      // and then resize ourselves to make the view that size.
      NSSize scrollViewSize = [_scrollView frame].size;
      NSSize previousViewSize = [[_scrollView class]
          contentSizeForFrameSize:scrollViewSize
          horizontalScrollerClass:[_scrollView hasHorizontalScroller] ? [NSScroller class] : Nil
            verticalScrollerClass:[_scrollView hasVerticalScroller] ? [NSScroller class] : Nil
                       borderType:[_scrollView borderType]
                      controlSize:NSControlSizeRegular
                    scrollerStyle:previousScrollerStyle];
      previousViewSize.width -= (defaultTextPadding() * 2.0);
      [self resizeWindowForViewSize:previousViewSize];
    }
  }
}

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder {
  [super encodeRestorableStateWithCoder:coder];
  // Normally you would just encode things that changed; however, since the only
  // invalidation we do is for scrollerStyle, this approach is fine for now.
  [coder encodeInteger:[NSScroller preferredScrollerStyle] forKey:@"scrollerStyle"];
}

- (void)resizeWindowForViewSize:(NSSize)size {
  NSWindow *window = [self window];
  NSRect origWindowFrame = [window frame];
  NSScrollerStyle scrollerStyle;
  if (![[self document] hasMultiplePages]) {
    size.width += (defaultTextPadding() * 2.0);
    scrollerStyle = [NSScroller preferredScrollerStyle];
  } else {
    scrollerStyle = NSScrollerStyleLegacy; // For the wrap-to-page case, which uses legacy
                                           // style scrollers for now
  }
  NSRect scrollViewRect = [[window contentView] frame];
  scrollViewRect.size = [[_scrollView class]
      frameSizeForContentSize:size
      horizontalScrollerClass:[_scrollView hasHorizontalScroller] ? [NSScroller class] : Nil
        verticalScrollerClass:[_scrollView hasVerticalScroller] ? [NSScroller class] : Nil
                   borderType:[_scrollView borderType]
                  controlSize:NSControlSizeRegular
                scrollerStyle:scrollerStyle];
  NSRect newFrame = [window frameRectForContentRect:scrollViewRect];
  newFrame.origin =
      NSMakePoint(origWindowFrame.origin.x, NSMaxY(origWindowFrame) - newFrame.size.height);
  [window setFrame:newFrame display:YES];
}

- (void)setupWindowForDocument {
  NSSize viewSize = [[self document] viewSize];
  [self setupTextViewForDocument];

  if (!NSEqualSizes(viewSize,
                    NSZeroSize)) { // Document has a custom view size that should be used
    [self resizeWindowForViewSize:viewSize];
  } else { // Set the window size from defaults...
    if (_hasMultiplePages) {
      [self resizeWindowForViewSize:[[_scrollView documentView] pageRectForPageNumber:0].size];
    } else {
      NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
      NSInteger windowHeight = [defaults integerForKey:WindowHeight];
      NSInteger windowWidth = [defaults integerForKey:WindowWidth];
      NSFont *font = [[self document] isRichText] ? [NSFont userFontOfSize:0.0]
                                                  : [NSFont userFixedPitchFontOfSize:0.0];
      NSSize size;
      size.height = ceil([[self layoutManager] defaultLineHeightForFont:font] * windowHeight);
      size.width = [@"x" sizeWithAttributes:[NSDictionary dictionaryWithObject:font
                                                                        forKey:NSFontAttributeName]]
                       .width;
      if (size.width == 0.0) {
        size.width =
            [@" " sizeWithAttributes:[NSDictionary dictionaryWithObject:font
                                                                 forKey:NSFontAttributeName]]
                .width; /* try for space width */
      }
      if (size.width == 0.0) {
        size.width = [font maximumAdvancement].width; /* or max width */
      }
      size.width = ceil(size.width * windowWidth);
      [self resizeWindowForViewSize:size];
    }
  }
}

- (void)windowDidLoad {
  [super windowDidLoad];

  // This creates the first text view
  [self setHasMultiplePages:[[self document] hasMultiplePages] force:YES];

  // This sets it up
  [self setupInitialTextViewSharedState];

  // This makes sure the window's UI (including text view shared state) is
  // updated to reflect the document
  [self setupWindowForDocument];

  // Changes to the zoom popup need to be communicated to the document
  if ([[self document] hasMultiplePages]) {
    [_scrollView setScaleFactor:[[self document] scaleFactor] adjustPopup:YES];
  }
  [_scrollView addObserver:self forKeyPath:@"scaleFactor" options:0 context:NULL];
  [[_scrollView verticalScroller] addObserver:self
                                   forKeyPath:@"scrollerStyle"
                                      options:0
                                      context:NULL];
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
  if (!_hasMultiplePages) { // If not wrap-to-page, use the default suggested
    return defaultFrame;
  } else {
    NSRect currentFrame = [window frame]; // Get the current size and location of the window
    NSRect standardFrame;
    NSSize paperSize = [[[self document] printInfo]
        paperSize]; // Get a frame size that fits the current printable page
    NSRect newScrollView;

    // Get a frame for the window content, which is a scrollView
    newScrollView.origin = NSZeroPoint;
    newScrollView.size = [[_scrollView class]
        frameSizeForContentSize:paperSize
        horizontalScrollerClass:[_scrollView hasHorizontalScroller] ? [NSScroller class] : Nil
          verticalScrollerClass:[_scrollView hasVerticalScroller] ? [NSScroller class] : Nil
                     borderType:[_scrollView borderType]
                    controlSize:NSControlSizeRegular
                  scrollerStyle:NSScrollerStyleLegacy];

    // The standard frame for the window is now the frame that will fit the
    // scrollView content
    standardFrame.size =
        [[window class] frameRectForContentRect:newScrollView styleMask:[window styleMask]].size;

    // Set the top left of the standard frame to be the same as that of the
    // current window
    standardFrame.origin.y = NSMaxY(currentFrame) - standardFrame.size.height;
    standardFrame.origin.x = currentFrame.origin.x;

    return standardFrame;
  }
}

- (void)windowDidResize:(NSNotification *)notification {
  [[self document] setTransient:NO]; // Since the user has taken an interest in the window,
                                     // clear the document's transient status

  if (!_isSettingSize) { // There is potential for recursion, but typically this
                         // is prevented in NSWindow which doesn't call this
                         // method if the frame doesn't change. However, just in
                         // case...
    _isSettingSize = YES;
    NSSize viewSize = [[_scrollView class]
        contentSizeForFrameSize:[_scrollView frame].size
        horizontalScrollerClass:[_scrollView hasHorizontalScroller] ? [NSScroller class] : Nil
          verticalScrollerClass:[_scrollView hasVerticalScroller] ? [NSScroller class] : Nil
                     borderType:[_scrollView borderType]
                    controlSize:NSControlSizeRegular
                  scrollerStyle:[NSScroller preferredScrollerStyle]];

    if (![[self document] hasMultiplePages]) {
      viewSize.width -= (defaultTextPadding() * 2.0);
    }
    [[self document] setViewSize:viewSize];
    _isSettingSize = NO;
  }
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
  if (!_hasMultiplePages) return;

  // If called during a view display cycle, defer page changes.
  if ([NSGraphicsContext currentContext]) {
    if (!_pageUpdateDeferred) {
      _pageUpdateDeferred = YES;
      dispatch_async(dispatch_get_main_queue(), ^{
        self->_pageUpdateDeferred = NO;
        [self _syncPages];
      });
    }
    return;
  }

  [self _handleLayoutForContainer:textContainer
                            atEnd:layoutFinishedFlag
                    layoutManager:layoutManager];
}

/* Deferred page sync — called after a display cycle that needed page changes. */
- (void)_syncPages {
  if (!_hasMultiplePages) return;
  NSLayoutManager *lm = [self layoutManager];
  NSArray *containers = [lm textContainers];
  if ([containers count] == 0) return;

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
    if (_addingPageCount > 0) return;

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
        if (tv) [removedTextViews addObject:tv];
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
