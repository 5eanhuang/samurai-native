//
//     ____    _                        __     _      _____
//    / ___\  /_\     /\/\    /\ /\    /__\   /_\     \_   \
//    \ \    //_\\   /    \  / / \ \  / \//  //_\\     / /\/
//  /\_\ \  /  _  \ / /\/\ \ \ \_/ / / _  \ /  _  \ /\/ /_
//  \____/  \_/ \_/ \/    \/  \___/  \/ \_/ \_/ \_/ \____/
//
//	Copyright Samurai development team and other contributors
//
//	http://www.samurai-framework.com
//
//	Permission is hereby granted, free of charge, to any person obtaining a copy
//	of this software and associated documentation files (the "Software"), to deal
//	in the Software without restriction, including without limitation the rights
//	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//	copies of the Software, and to permit persons to whom the Software is
//	furnished to do so, subject to the following conditions:
//
//	The above copyright notice and this permission notice shall be included in
//	all copies or substantial portions of the Software.
//
//	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//	THE SOFTWARE.
//

#import "Samurai_CSSSelectorChecker.h"

#import "selector.h"

#import "_pragma_push.h"

#if (TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR)

// ----------------------------------
// Source code
// ----------------------------------

#pragma mark -

#undef  ASSERT_NOT_REACHED
#define ASSERT_NOT_REACHED NSAssert(NO, @"ASSERT_NOT_REACHED")

static bool parseNth(const KatanaSelector * selector);
static bool matchNth(const KatanaSelector * selector, int count);

#pragma mark -

@implementation SamuraiCSSSelectorCheckerMatchResult
@end

#pragma mark -

@implementation SamuraiCSSSelectorCheckingContext

- initWithContext:(SamuraiCSSSelectorCheckingContext *)context
{
    self = [super init];
    if (self) {
        _element = context.element;
        _previousElement = context.previousElement;
        _pseudoId = context.pseudoId;
    }
    return self;
}

@end

#pragma mark -

@implementation SamuraiCSSSelectorChecker

// Recursive check of selectors and combinators
// It can return 4 different values:
// * SelectorMatches          - the selector matches the element e
// * SelectorFailsLocally     - the selector fails for the element e
// * SelectorFailsAllSiblings - the selector fails for e and any sibling of e
// * SelectorFailsCompletely  - the selector fails for e and any sibling or ancestor of e
- (SamuraiCSSSelectorMatch)match:(SamuraiCSSSelectorCheckingContext *)context result:(SamuraiCSSSelectorCheckerMatchResult *)result
{
    // first selector has to match
    unsigned specificity = 0;

    if ( ![self checkOne:context specificity:&specificity] )
        return SamuraiCSSSelectorFailsLocally;
    
    // ::pseudo
    if ( context.selector->match == KatanaSelectorMatchPseudoElement )
    {
        // TODO: @(QFish) support ::PseudoElement
        /*
        if (katana_selector_is_content_pseudo_element) {
            if (!matchesCustomPseudoElement(context.element, *context.selector))
                return SelectorFailsLocally;
        } else if (context.selector->isContentPseudoElement()) {
            if (!context.element->isInShadowTree() || !context.element->isInsertionPoint())
                return SelectorFailsLocally;
        } else if (context.selector->isShadowPseudoElement()) {
            if (!context.element->isInShadowTree() || !context.previousElement)
                return SelectorFailsCompletely;
        } else {
            if ((!context.elementStyle && m_mode == ResolvingStyle) || m_mode == QueryingRules)
                return SelectorFailsLocally;
            
            PseudoId pseudoId = CSSSelector::pseudoId(context.selector->pseudo);
            if (pseudoId == FIRST_LETTER)
                context.element->document().styleEngine().setUsesFirstLetterRules(YES);
            if (pseudoId != NOPSEUDO && m_mode != SharingRules && result)
                result->dynamicPseudo = pseudoId;
        }
         */
    }

    // Prepare next selector (mine)
    if ( NULL == context.selector->tagHistory ) {
        if ( result )
            result.specificity += specificity;
        return SamuraiCSSSelectorMatches;
    }
    
    // TODO: @(QFish) Using isLastInTagHistory
    /*
    // Prepare next selector (blink)
    if (context.selector->isLastInTagHistory()) {
        if (scopeContainsLastMatchedElement(context)) {
            if (result)
                result->specificity += specificity;
            return SelectorMatches;
        }
        return SelectorFailsLocally;
    }
     */

    SamuraiCSSSelectorMatch match;
    if ( context.selector->relation != KatanaSelectorRelationSubSelector ) {
        // Abort if the next selector would exceed the scope.
        if ( [self nextSelectorExceedsScope:context] )
            return SamuraiCSSSelectorFailsCompletely;

        // Bail-out if this selector is irrelevant for the pseudoId
        if (context.pseudoId != NOPSEUDO && (!result || context.pseudoId != result.dynamicPseudo))
            return SamuraiCSSSelectorFailsCompletely;

        if ( result ) {
            // TODO: @(QFish) What dose PseudoId really mean ?
            /*
            TemporaryChange<PseudoId> dynamicPseudoScope(result->dynamicPseudo, NOPSEUDO);
            match = matchForRelation(context, siblingTraversalStrategy, result);
             */
             
            match = [self matchForRelation:context result:result];
        } else {
            return [self matchForRelation:context result:nil];
        }
    } else {
        match = [self matchForSubSelector:context result:result];
    }
    if ( match != SamuraiCSSSelectorMatches || !result )
        return match;

    result.specificity += specificity;
    return SamuraiCSSSelectorMatches;
}

- (BOOL)nextSelectorExceedsScope:(SamuraiCSSSelectorCheckingContext *)context
{
    return NO;
}

static inline SamuraiCSSSelectorCheckingContext * prepareNextContextForRelation(SamuraiCSSSelectorCheckingContext* context)
{
    SamuraiCSSSelectorCheckingContext * nextContext =
        [[SamuraiCSSSelectorCheckingContext alloc] initWithContext:context];
    ASSERT(context.selector->tagHistory);
    nextContext.selector = context.selector->tagHistory;
    return nextContext;
}

static id<SamuraiCSSProtocol> parentElement(const SamuraiCSSSelectorCheckingContext* context)
{
    // - If context.scope is a shadow root, we should walk up to its shadow host.
    // - If context.scope is some element in some shadow tree and querySelector initialized the context,
    //   e.g. shadowRoot.querySelector(':host *'),
    //   (a) context.element has the same treescope as context.scope, need to walk up to its shadow host.
    //   (b) Otherwise, should not walk up from a shadow root to a shadow host.
    
    // TODO: (@QFish) There is no need to support shadow bla bla for right now.
    /*
    if (context.scope && (context.scope == context.element->containingShadowRoot() || context.scope->treeScope() == context.element->treeScope()))
        return context.element->parentOrShadowHostElement();
     */
    return [context.element cssParent];
}

- (SamuraiCSSSelectorMatch)matchForRelation:(SamuraiCSSSelectorCheckingContext *)context result:(SamuraiCSSSelectorCheckerMatchResult *)result
{
    SamuraiCSSSelectorCheckingContext * nextContext = prepareNextContextForRelation(context);
    
    nextContext.previousElement = context.element;
    
    KatanaSelectorRelation relation = context.selector->relation;
    
    // TODO: (@QFish)
    /*
    // Disable :visited matching when we see the first link or try to match anything else than an ancestors.
    if (!context.isSubSelector && (context.element->isLink() || (relation != CSSSelector::Descendant && relation != CSSSelector::Child)))
        nextContext.visitedMatchType = VisitedMatchDisabled;
     */
    nextContext.pseudoId = NOPSEUDO;
    
    switch (relation) {
        case KatanaSelectorRelationDescendant:
//            if (context.selector->relationIsAffectedByPseudoContent()) {
//                for (Element* element = context.element; element; element = element->parentElement()) {
//                    if (matchForShadowDistributed(element, siblingTraversalStrategy, nextContext, result) == SelectorMatches)
//                        return SelectorMatches;
//                }
//                return SamuraiCSSSelectorFailsCompletely;
//            }
            nextContext.isSubSelector = NO;
            nextContext.elementStyle = 0;
            
//            if (selectorMatchesShadowRoot(nextContext.selector))
//                return matchForPseudoShadow(context.element->containingShadowRoot(), nextContext, siblingTraversalStrategy, result);
            
            for (nextContext.element = parentElement(context); nextContext.element; nextContext.element = parentElement(nextContext)) {
                SamuraiCSSSelectorMatch match = [self match:nextContext result:result];
                if (match == SamuraiCSSSelectorMatches || match == SamuraiCSSSelectorFailsCompletely)
                    return match;
                if ([self nextSelectorExceedsScope:nextContext])
                    return SamuraiCSSSelectorFailsCompletely;
            }
            return SamuraiCSSSelectorFailsCompletely;
        case KatanaSelectorRelationChild:
        {
//            if (context.selector->relationIsAffectedByPseudoContent())
//                return matchForShadowDistributed(context.element, siblingTraversalStrategy, nextContext, result);
            
            nextContext.isSubSelector = NO;
            nextContext.elementStyle = 0;
            
//            if (selectorMatchesShadowRoot(nextContext.selector))
//                return matchForPseudoShadow(context.element->parentNode(), nextContext, siblingTraversalStrategy, result);
            
            nextContext.element = parentElement(context);
            if (!nextContext.element)
                return SamuraiCSSSelectorFailsCompletely;
            return [self match:nextContext result:result];
        }
        case KatanaSelectorRelationDirectAdjacent:
        {
            // Shadow roots can't have sibling elements
//            if (selectorMatchesShadowRoot(nextContext.selector))
//                return SamuraiCSSSelectorFailsCompletely;
            
//            if (m_mode == ResolvingStyle) {
//                if (ContainerNode* parent = context.element->parentElementOrShadowRoot())
//                    parent->setChildrenAffectedByDirectAdjacentRules();
//            }
            nextContext.element = [context.element cssPreviousSibling];
            if (!nextContext.element)
                return SamuraiCSSSelectorFailsAllSiblings;
            nextContext.isSubSelector = NO;
            nextContext.elementStyle = 0;
            return [self match:nextContext result:result];
        }
        case KatanaSelectorRelationIndirectAdjacent:
        {
            // Shadow roots can't have sibling elements
//            if (selectorMatchesShadowRoot(nextContext.selector))
//                return SamuraiCSSSelectorFailsCompletely;
            
//            if (m_mode == ResolvingStyle) {
//                if (ContainerNode* parent = context.element->parentElementOrShadowRoot())
//                    parent->setChildrenAffectedByIndirectAdjacentRules();
//            }
            nextContext.element = [context.element cssPreviousSibling];
            nextContext.isSubSelector = NO;
            nextContext.elementStyle = 0;
            for (; nextContext.element; nextContext.element = [nextContext.element cssPreviousSibling]) {
                SamuraiCSSSelectorMatch match = [self match:nextContext result:result];
                if (match == SamuraiCSSSelectorMatches
                    || match == SamuraiCSSSelectorFailsAllSiblings
                    || match == SamuraiCSSSelectorFailsCompletely)
                    return match;
            };
            return SamuraiCSSSelectorFailsAllSiblings;
        }
        case KatanaSelectorRelationShadowPseudo:
        {
            // If we're in the same tree-scope as the scoping element, then following a shadow descendant combinator would escape that and thus the scope.
//            if (context.scope && context.scope->shadowHost() && context.scope->shadowHost()->treeScope() == context.element->treeScope())
//                return SamuraiCSSSelectorFailsCompletely;
            
//            Element* shadowHost = context.element->shadowHost();
//            if (!shadowHost)
//                return SelectorFailsCompletely;
//            nextContext.element = shadowHost;
//            nextContext.isSubSelector = NO;
//            nextContext.elementStyle = 0;
//            return [self match:nextContext result:result];
            return  SamuraiCSSSelectorFailsCompletely;
        }
        case KatanaSelectorRelationShadowDeep:
        {
//            if (context.selector->relationIsAffectedByPseudoContent()) {
//                for (Element* element = context.element; element; element = parentOrShadowHostButDisallowEscapingUserAgentShadowTree(*element)) {
//                    if (matchForShadowDistributed(element, siblingTraversalStrategy, nextContext, result) == SelectorMatches)
//                        return SelectorMatches;
//                }
//                return SamuraiCSSSelectorFailsCompletely;
//            }
            
//            nextContext.isSubSelector = NO;
//            nextContext.elementStyle = 0;
//            for (nextContext.element = parentOrShadowHostButDisallowEscapingUserAgentShadowTree(*context.element); nextContext.element; nextContext.element = parentOrShadowHostButDisallowEscapingUserAgentShadowTree(*nextContext.element)) {
//                SamuraiCSSSelectorMatch match = [self match:nextContext result:result];
//                if (match == SamuraiCSSSelectorMatches
//                    || match == SamuraiCSSSelectorFailsCompletely)
//                    return match;
//                if ([self nextSelectorExceedsScope:nextContext])
//                    return SamuraiCSSSelectorFailsCompletely;
//            }
            return SamuraiCSSSelectorFailsCompletely;
        }
        case KatanaSelectorRelationSubSelector:
            ASSERT_NOT_REACHED;
    }

    ASSERT_NOT_REACHED;
    return SamuraiCSSSelectorFailsCompletely;
}

- (SamuraiCSSSelectorMatch)matchForSubSelector:(SamuraiCSSSelectorCheckingContext *)context result:(SamuraiCSSSelectorCheckerMatchResult *)result
{
    SamuraiCSSSelectorCheckingContext * nextContext = prepareNextContextForRelation(context);
    //    PseudoId dynamicPseudo = result ? result->dynamicPseudo : NOPSEUDO;
    // a selector is invalid if something follows a pseudo-element
    // We make an exception for scrollbar pseudo elements and allow a set of pseudo classes (but nothing else)
    // to follow the pseudo elements.
    //    nextContext.hasScrollbarPseudo = dynamicPseudo != NOPSEUDO && (context.scrollbar || dynamicPseudo == SCROLLBAR_CORNER || dynamicPseudo == RESIZER);
    //    nextContext.hasSelectionPseudo = dynamicPseudo == SELECTION;
    //    if ((context.elementStyle || m_mode == CollectingCSSRules || m_mode == CollectingStyleRules || m_mode == QueryingRules) && dynamicPseudo != NOPSEUDO
    //        && !nextContext.hasSelectionPseudo
    //        && !(nextContext.hasScrollbarPseudo && nextContext.selector->match() == CSSSelector::PseudoClass))
    //        return SamuraiCSSSelectorFailsLocally;
    nextContext.isSubSelector = YES;
    return  [self match:nextContext result:result];
}

- (BOOL)checkOne:(SamuraiCSSSelectorCheckingContext *)context specificity:(unsigned *)specificity
{
    ASSERT(context.element);
    id<SamuraiCSSProtocol> element = context.element;
    ASSERT(context.selector);
    const KatanaSelector * selector = context.selector;

    // TODO: @(QFish) ShadowTree
//    bool elementIsHostInItsShadowTree = isHostInItsShadowTree(element, context.scope);
//    
//    // Only :host and :host-context() should match the host: http://drafts.csswg.org/css-scoping/#host-element
//    if (elementIsHostInItsShadowTree && (!selector.isHostPseudoClass()
//                                         && !context.treatShadowHostAsNormalScope
//                                         && selector.match() != CSSSelector::PseudoElement))
//        return NO;
    
    switch ( selector->match ) {
        case KatanaSelectorMatchTag:
            return [self tagMatches:element tag:selector->tag];
        case KatanaSelectorMatchClass:
        {
            if ( selector->data->value != NULL
                    && [element cssClasses]
                    && [element cssClasses].count )
            {
                NSString * value = [NSString stringWithUTF8String:selector->data->value];
                return [[element cssClasses] containsObject:value];
            }
			return NO;
        }
        case KatanaSelectorMatchId:
        {
            if ( selector->data->value != NULL && [element cssId] )
            {
                NSString * value = [NSString stringWithUTF8String:selector->data->value];
                return [[element cssId] isEqualToString:value];
            }
			return NO;
        }
        case KatanaSelectorMatchAttributeExact:
        case KatanaSelectorMatchAttributeSet:
        case KatanaSelectorMatchAttributeHyphen:
        case KatanaSelectorMatchAttributeList:
        case KatanaSelectorMatchAttributeContain:
        case KatanaSelectorMatchAttributeBegin:
        case KatanaSelectorMatchAttributeEnd:
            return [self anyAttributeMatches:element match:selector->match selector:selector];
//
        case KatanaSelectorMatchPseudoClass:
//            return checkPseudoClass(context, siblingTraversalStrategy, specificity);
            return [self checkPseudoClass:context specificity:specificity];
        case KatanaSelectorMatchPseudoElement:
            return NO;
//            return checkPseudoElement(context, siblingTraversalStrategy);
            
        case KatanaSelectorMatchPagePseudoClass:
            // FIXME: what?
            return YES;
        case KatanaSelectorMatchUnknown:
            // FIXME: what?
            return YES;
    }
    // TODO: @(QFish) for debug
    ASSERT_NOT_REACHED;
    return YES;
}

static inline bool attributeMatches(const KatanaQualifiedName* qualifiedName, NSString * local, NSString * prefix, NSString * uri)
{
	if ( strcasecmp(qualifiedName->local, local.UTF8String) )
		return false;
	// TODO:(@QFish:check prefix and namespace of element)
	return true;
//	return qualifiedName.prefix() == starAtom || qualifiedName.namespaceURI() == namespaceURI();
}

static inline bool isHTMLSpace(char character)
{
	// Histogram from Apple's page load test combined with some ad hoc browsing some other test suites.
	//
	//     82%: 216330 non-space characters, all > U+0020
	//     11%:  30017 plain space characters, U+0020
	//      5%:  12099 newline characters, U+000A
	//      2%:   5346 tab characters, U+0009
	//
	// No other characters seen. No U+000C or U+000D, and no other control characters.
	// Accordingly, we check for non-spaces first, then space, then newline, then tab, then the other characters.
	
	return character <= ' ' && (character == ' ' || character == '\n' || character == '\t' || character == '\r' || character == '\f');
}

static inline bool containsHTMLSpace(const char * string)
{
	size_t length = strlen(string);
	for (size_t i = 0; i < length; ++i)
		if (isHTMLSpace(string[i]))
			return true;
	return false;
}

static bool attributeValueMatches(NSString * value, KatanaSelectorMatch match, const char * selectorValue)
{
	if (!value)
		return false;
	
	switch (match) {
		case KatanaSelectorMatchAttributeExact:
			if (0 != strcasecmp(selectorValue, value.UTF8String))
				return false;
			break;
		case KatanaSelectorMatchAttributeList:
		{
			// Ignore empty selectors or selectors containing HTML spaces
			if (selectorValue == NULL || containsHTMLSpace(selectorValue))
				return false;
			NSArray * words = [value componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			bool found = false;
			for ( NSString * word in words ) {
				if ( !strcasecmp(selectorValue, word.UTF8String) ) {
					found = true;
					break;
				}
			}
			return found;
			break;
		}
		case KatanaSelectorMatchAttributeContain:
			if (![value containsString:[NSString stringWithUTF8String:selectorValue]] || NULL == selectorValue)
				return false;
			break;
		case KatanaSelectorMatchAttributeBegin:
			if (![value hasPrefix:[NSString stringWithUTF8String:selectorValue]] || NULL == selectorValue)
				return false;
			break;
		case KatanaSelectorMatchAttributeEnd:
			if (![value hasSuffix:[NSString stringWithUTF8String:selectorValue]] || NULL == selectorValue)
				return false;
			break;
		case KatanaSelectorMatchAttributeHyphen:
		{
			size_t length = strlen(selectorValue);
			if (value.length < length)
				return false;
			if (![value hasPrefix:[NSString stringWithUTF8String:selectorValue]])
				return false;
			// It they start the same, check for exact match or following '-':
			if (value.length != length && [value characterAtIndex:length] != '-')
				return false;
		}
			break;
		case KatanaSelectorMatchPseudoClass:
		case KatanaSelectorMatchPseudoElement:
		default:
			break;
	}
	
	return true;
}

- (BOOL)anyAttributeMatches:(id<SamuraiCSSProtocol>)element match:(KatanaSelectorMatch)match selector:(const KatanaSelector *)selector
{
    const KatanaQualifiedName * selectorAttr = selector->data->attribute;
    const char * selectorValue = selector->data->value;
	NSDictionary * attributes = [element cssAttributes];
//	NSLog( @"%s", selectorAttr->local );
//	NSLog( @"%s", selectorValue );
//	NSLog( @"%@", attributes );
	
	for ( NSString * key in attributes.allKeys )
	{
		if ( !attributeMatches(selectorAttr, key, nil, nil) )
			continue;
		
		if (attributeValueMatches(attributes[key], selector->match, selectorValue))
			return true;
	}
	
    return false;
}

- (BOOL)checkPseudoClass:(SamuraiCSSSelectorCheckingContext *)context specificity:(unsigned*) specificity
{
    id<SamuraiCSSProtocol> element = context.element;
    const KatanaSelector * selector = context.selector;
    
    // Handle :not up front.
    if (selector->pseudo == KatanaPseudoNot) {
        SamuraiCSSSelectorCheckingContext * subContext =
        [[SamuraiCSSSelectorCheckingContext alloc] initWithContext:context];
        subContext.isSubSelector = true;
        ASSERT(selector->data->selectors);
        for (subContext.selector = selector->data->selectors->data[0]; subContext.selector; subContext.selector = subContext.selector->tagHistory) {
            // :not cannot nest. I don't really know why this is a
            // restriction in CSS3, but it is, so let's honor it.
            // the parser enforces that this never occurs
            ASSERT(subContext.selector->pseudo != KatanaPseudoNot);
            // We select between :visited and :link when applying. We don't know which one applied (or not) yet.
            // TODO @(QFish) Don not handle :visited or :link for right now
            /*
            if (subContext.selector->pseudo == KatanaPseudoVisited || (subContext.selector->pseudo == KatanaPseudoLink && subContext.visitedMatchType == VisitedMatchEnabled))
                return true;
            // context.scope is not available if m_mode == SharingRules.
            // We cannot determine whether :host or :scope matches a given element or not.
            if (m_mode == SharingRules && (subContext.selector->isHostPseudoClass() || subContext.selector->pseudo == KatanaPseudoScope))
                return true;
             */
            if (![self checkOne:context specificity:nil])
                return true;
        }
        return false;
    }
    
    /*
    if (context.hasScrollbarPseudo) {
        // CSS scrollbars match a specific subset of pseudo classes, and they have specialized rules for each
        // (since there are no elements involved).
        return checkScrollbarPseudoClass(context, &element.document(), selector);
    }
    
    if (context.hasSelectionPseudo) {
        if (selector.pseudo == KatanaPseudoWindowInactive)
            return !element.document().page()->focusController().isActive();
    }
     */
    
    switch (selector->pseudo) {
        case KatanaPseudoNot:
            ASSERT_NOT_REACHED;
            break; // Already handled up above.
        case KatanaPseudoEmpty:
        {
            bool result = true;
//            for (Node* n = element.firstChild(); n; n = n->nextSibling()) {
//                if (n->isElementNode()) {
//                    result = false;
//                    break;
//                }
//                if (n->isTextNode()) {
//                    Text* textNode = toText(n);
//                    if (!textNode->data().isEmpty()) {
//                        result = false;
//                        break;
//                    }
//                }
//            }
//            if (m_mode == ResolvingStyle) {
//                element.setStyleAffectedByEmpty();
//                if (context.elementStyle)
//                    context.elementStyle->setEmptyState(result);
//                else if (element.computedStyle() && (element.document().styleEngine().usesSiblingRules() || element.computedStyle()->unique()))
//                    element.mutableComputedStyle()->setEmptyState(result);
//            }
            return result;
        }
        case KatanaPseudoFirstChild:
            /*
            if (ContainerNode* parent = element.parentElementOrDocumentFragment()) {
                if (m_mode == ResolvingStyle) {
                    parent->setChildrenAffectedByFirstChildRules();
                    element.setAffectedByFirstChildRules();
                }
                return siblingTraversalStrategy.isFirstChild(element);
            }
             */
            return ![element cssPreviousSibling]; // previsous sibling is null
            break;
        case KatanaPseudoFirstOfType:
            /*
            if (ContainerNode* parent = element.parentElementOrDocumentFragment()) {
                if (m_mode == ResolvingStyle)
                    parent->setChildrenAffectedByForwardPositionalRules();
                return siblingTraversalStrategy.isFirstOfType(element, element.tagQName());
            }
             */
            return false;
            break;
        case KatanaPseudoLastChild:
        {
            /*
             if (ContainerNode* parent = element.parentElementOrDocumentFragment()) {
             if (m_mode == ResolvingStyle) {
             parent->setChildrenAffectedByLastChildRules();
             element.setAffectedByLastChildRules();
             }
             if (!parent->isFinishedParsingChildren())
             return false;
             return siblingTraversalStrategy.isLastChild(element);
             }
             */
            return ![element cssFollowingSibling]; // following sibling is null
        }
            break;
        case KatanaPseudoLastOfType:
//            if (ContainerNode* parent = element.parentElementOrDocumentFragment()) {
//                if (m_mode == ResolvingStyle)
//                    parent->setChildrenAffectedByBackwardPositionalRules();
//                if (!parent->isFinishedParsingChildren())
//                    return false;
//                return siblingTraversalStrategy.isLastOfType(element, element.tagQName());
//            }
            return false;
            break;
        case KatanaPseudoOnlyChild:
        {
//            if (ContainerNode* parent = element.parentElementOrDocumentFragment()) {
//                if (m_mode == ResolvingStyle) {
//                    parent->setChildrenAffectedByFirstChildRules();
//                    parent->setChildrenAffectedByLastChildRules();
//                    element.setAffectedByFirstChildRules();
//                    element.setAffectedByLastChildRules();
//                }
//                if (!parent->isFinishedParsingChildren())
//                    return false;
//                return siblingTraversalStrategy.isFirstChild(element) && siblingTraversalStrategy.isLastChild(element);
//            }
            return ![element cssPreviousSibling] && ![element cssFollowingSibling];
        }
            break;
        case KatanaPseudoOnlyOfType:
//            // FIXME: This selector is very slow.
//            if (ContainerNode* parent = element.parentElementOrDocumentFragment()) {
//                if (m_mode == ResolvingStyle) {
//                    parent->setChildrenAffectedByForwardPositionalRules();
//                    parent->setChildrenAffectedByBackwardPositionalRules();
//                }
//                if (!parent->isFinishedParsingChildren())
//                    return false;
//                return siblingTraversalStrategy.isFirstOfType(element, element.tagQName()) && siblingTraversalStrategy.isLastOfType(element, element.tagQName());
//            }
            return false;
            break;
        case KatanaPseudoNthChild:
        {
            if (!parseNth(selector))
                break;
//            if (ContainerNode* parent = element.parentElementOrDocumentFragment()) {
//                if (m_mode == ResolvingStyle)
//                    parent->setChildrenAffectedByForwardPositionalRules();
                return matchNth(selector, 1 + (int)[element cssPreviousSiblings].count);
//            }
        }
            break;
        case KatanaPseudoNthOfType: 
//            if (!selector.parseNth())
//                break;
//            if (ContainerNode* parent = element.parentElementOrDocumentFragment()) {
//                if (m_mode == ResolvingStyle)
//                    parent->setChildrenAffectedByForwardPositionalRules();
//                return selector.matchNth(1 + siblingTraversalStrategy.countElementsOfTypeBefore(element, element.tagQName()));
//            }
            return false;
            break;
        case KatanaPseudoNthLastChild:
            if (!parseNth(selector))
                break;
//            if (ContainerNode* parent = element.parentElementOrDocumentFragment()) {
//                if (m_mode == ResolvingStyle)
//                    parent->setChildrenAffectedByBackwardPositionalRules();
//                if (!parent->isFinishedParsingChildren())
//                    return false;
                return matchNth(selector, 1 + (int)[element cssFollowingSiblings].count);
//            }
//            break;
        case KatanaPseudoNthLastOfType:
//            if (!selector.parseNth())
//                break;
//            if (ContainerNode* parent = element.parentElementOrDocumentFragment()) {
//                if (m_mode == ResolvingStyle)
//                    parent->setChildrenAffectedByBackwardPositionalRules();
//                if (!parent->isFinishedParsingChildren())
//                    return false;
//                return selector.matchNth(1 + siblingTraversalStrategy.countElementsOfTypeAfter(element, element.tagQName()));
//            }
//            break;
        case KatanaPseudoTarget:
//            return element == element.document().cssTarget();
        case KatanaPseudoAny:
//        {
//            SelectorCheckingContext subContext(context);
//            subContext.isSubSelector = true;
//            ASSERT(selector.selectorList());
//            for (subContext.selector = selector.selectorList()->first(); subContext.selector; subContext.selector = CSSSelectorList::next(*subContext.selector)) {
//                if (match(subContext, siblingTraversalStrategy) == SelectorMatches)
//                    return true;
//            }
//        }
//            break;
        case KatanaPseudoAutofill:
//            return element.isFormControlElement() && toHTMLFormControlElement(element).isAutofilled();
        case KatanaPseudoAnyLink:
        case KatanaPseudoLink:
//            return element.isLink();
        case KatanaPseudoVisited:
//            return element.isLink() && context.visitedMatchType == VisitedMatchEnabled;
        case KatanaPseudoDrag:
//            if (m_mode == ResolvingStyle) {
//                if (context.elementStyle)
//                    context.elementStyle->setAffectedByDrag();
//                else
//                    element.setChildrenOrSiblingsAffectedByDrag();
//            }
//            return element.layoutObject() && element.layoutObject()->isDragging();
        case KatanaPseudoFocus:
//            if (m_mode == ResolvingStyle) {
//                if (context.elementStyle)
//                    context.elementStyle->setAffectedByFocus();
//                else
//                    element.setChildrenOrSiblingsAffectedByFocus();
//            }
//            return matchesFocusPseudoClass(element);
        case KatanaPseudoHover:
//            if (m_mode == ResolvingStyle) {
//                if (context.elementStyle)
//                    context.elementStyle->setAffectedByHover();
//                else
//                    element.setChildrenOrSiblingsAffectedByHover();
//            }
//            if (!shouldMatchHoverOrActive(context))
//                return false;
//            if (InspectorInstrumentation::forcePseudoState(&element, KatanaPseudoHover))
//                return true;
//            return element.hovered();
        case KatanaPseudoActive:
//            if (m_mode == ResolvingStyle) {
//                if (context.elementStyle)
//                    context.elementStyle->setAffectedByActive();
//                else
//                    element.setChildrenOrSiblingsAffectedByActive();
//            }
//            if (!shouldMatchHoverOrActive(context))
//                return false;
//            if (InspectorInstrumentation::forcePseudoState(&element, KatanaPseudoActive))
//                return true;
//            return element.active();
        case KatanaPseudoEnabled:
//            if (element.isFormControlElement() || isHTMLOptionElement(element) || isHTMLOptGroupElement(element))
//                return !element.isDisabledFormControl();
//            if (isHTMLAnchorElement(element) || isHTMLAreaElement(element))
//                return element.isLink();
//            break;
        case KatanaPseudoFullPageMedia:
//            return element.document().isMediaDocument();
        case KatanaPseudoDefault:
//            return element.isDefaultButtonForForm();
        case KatanaPseudoDisabled:
//            // TODO(esprehn): Why not just always return isDisabledFormControl()?
//            // Can it be true for elements not in the list below?
//            if (element.isFormControlElement() || isHTMLOptionElement(element) || isHTMLOptGroupElement(element))
//                return element.isDisabledFormControl();
//            break;
        case KatanaPseudoReadOnly:
//            return element.matchesReadOnlyPseudoClass();
        case KatanaPseudoReadWrite:
//            return element.matchesReadWritePseudoClass();
        case KatanaPseudoOptional:
//            return element.isOptionalFormControl();
        case KatanaPseudoRequired:
//            return element.isRequiredFormControl();
        case KatanaPseudoValid:
//            if (m_mode == ResolvingStyle)
//                element.document().setContainsValidityStyleRules();
//            return element.matchesValidityPseudoClasses() && element.isValidElement();
        case KatanaPseudoInvalid:
//            if (m_mode == ResolvingStyle)
//                element.document().setContainsValidityStyleRules();
//            return element.matchesValidityPseudoClasses() && !element.isValidElement();
        case KatanaPseudoChecked:
//        {
//            if (isHTMLInputElement(element)) {
//                HTMLInputElement& inputElement = toHTMLInputElement(element);
//                // Even though WinIE allows checked and indeterminate to
//                // co-exist, the CSS selector spec says that you can't be
//                // both checked and indeterminate. We will behave like WinIE
//                // behind the scenes and just obey the CSS spec here in the
//                // test for matching the pseudo.
//                if (inputElement.shouldAppearChecked() && !inputElement.shouldAppearIndeterminate())
//                    return true;
//            } else if (isHTMLOptionElement(element) && toHTMLOptionElement(element).selected())
//                return true;
//            break;
//        }
        case KatanaPseudoIndeterminate:
//            return element.shouldAppearIndeterminate();
        case KatanaPseudoRoot:
//            return element == element.document().documentElement();
        case KatanaPseudoLang:
//        {
//            AtomicString value;
//            if (element.isVTTElement())
//                value = toVTTElement(element).language();
//            else
//                value = element.computeInheritedLanguage();
//            const AtomicString& argument = selector.argument();
//            if (value.isEmpty() || !value.startsWith(argument, TextCaseInsensitive))
//                break;
//            if (value.length() != argument.length() && value[argument.length()] != '-')
//                break;
//            return true;
//        }
        case KatanaPseudoFullScreen:
            // While a Document is in the fullscreen state, and the document's current fullscreen
            // element is an element in the document, the 'full-screen' pseudoclass applies to
            // that element. Also, an <iframe>, <object> or <embed> element whose child browsing
            // context's Document is in the fullscreen state has the 'full-screen' pseudoclass applied.
//            if (isHTMLFrameElementBase(element) && element.containsFullScreenElement())
//                return true;
//            return Fullscreen::isActiveFullScreenElement(element);
        case KatanaPseudoFullScreenAncestor:
//            return element.containsFullScreenElement();
        case KatanaPseudoFullScreenDocument:
            // While a Document is in the fullscreen state, the 'full-screen-document' pseudoclass applies
            // to all elements of that Document.
//            return Fullscreen::isFullScreen(element.document());
        case KatanaPseudoInRange:
//            if (m_mode == ResolvingStyle)
//                element.document().setContainsValidityStyleRules();
//            return element.isInRange();
        case KatanaPseudoOutOfRange:
//            if (m_mode == ResolvingStyle)
//                element.document().setContainsValidityStyleRules();
//            return element.isOutOfRange();
        case KatanaPseudoFutureCue:
//            return element.isVTTElement() && !toVTTElement(element).isPastNode();
        case KatanaPseudoPastCue:
//            return element.isVTTElement() && toVTTElement(element).isPastNode();
        case KatanaPseudoScope:
//            if (m_mode == SharingRules)
//                return true;
//            if (context.scope)
//                return context.scope == element;
//            return element == element.document().documentElement();
        case KatanaPseudoUnresolved:
//            return element.isUnresolvedCustomElement();
        case KatanaPseudoHost:
        case KatanaPseudoHostContext:
//            return checkPseudoHost(context, siblingTraversalStrategy, specificity);
        case KatanaPseudoSpatialNavigationFocus:
//            return context.isUARule && matchesSpatialNavigationFocusPseudoClass(element);
        case KatanaPseudoListBox:
//            return context.isUARule && matchesListBoxPseudoClass(element);
        case KatanaPseudoHorizontal:
        case KatanaPseudoVertical:
        case KatanaPseudoDecrement:
        case KatanaPseudoIncrement:
        case KatanaPseudoStart:
        case KatanaPseudoEnd:
        case KatanaPseudoDoubleButton:
        case KatanaPseudoSingleButton:
        case KatanaPseudoNoButton:
        case KatanaPseudoCornerPresent:
        case KatanaPseudoWindowInactive:
            return false;
        case KatanaPseudoUnknown:
            // TODO: @(QFish:high) support custom pseudo
            return true;
        case KatanaPseudoNotParsed:
        default:
            ASSERT_NOT_REACHED;
            break;
    }
    return false;
}

- (BOOL)tagMatches:(id<SamuraiCSSProtocol>)element tag:(KatanaQualifiedName *)tag
{
    if ( NULL == tag )
        return YES;
    
    NSString * elementTag = [element cssTag];
    
    if ( elementTag )
    {
        if ( !strcasecmp(elementTag.UTF8String, tag->local) )
            return YES;
    }
    
    if ( !strcasecmp("*", tag->local) )
        return YES;
    
    return NO;
}

@end

// a helper function for parsing nth-arguments
static bool parseNth(const KatanaSelector * selector)
{
    NSString* argument = [NSString stringWithUTF8String:selector->data->argument].lowercaseString;
    
    if ( !argument && !argument.length )
        return false;
    
    int nthA = 0;
    int nthB = 0;
    if ( [argument isEqualToString:@"odd"] ) {
        nthA = 2;
        nthB = 1;
    } else if ( [argument isEqualToString:@"even"] ) {
        nthA = 2;
        nthB = 0;
    } else {
        NSRange range = [argument rangeOfString:@"n"];
        NSUInteger n = range.location;
        if (n != NSNotFound) {
            if ([argument hasPrefix:@"-"]) {
                if (n == 1)
                    nthA = -1; // -n == -1n
                else
                    nthA = [argument substringToIndex:n].intValue;
            } else if (!n) {
                nthA = 1; // n == 1n
            } else {
                nthA = [argument substringToIndex:n].intValue;
            }
            
            range = [argument rangeOfString:@"+"
                                    options:NSCaseInsensitiveSearch
                                      range:NSMakeRange(n, argument.length - n)];
            
            NSUInteger p = range.location;
            if (p != NSNotFound) {
                nthB = [argument substringWithRange:NSMakeRange(p+1, argument.length - p - 1)].intValue;
            } else {
                range = [argument rangeOfString:@"-"
                                        options:NSCaseInsensitiveSearch
                                          range:NSMakeRange(n, argument.length - n)];
                p = range.location;
                if (p != NSNotFound)
                    nthB = -[argument substringWithRange:NSMakeRange(p+1, argument.length - p - 1)].intValue;
            }
        } else {
            nthB = argument.intValue;
        }
    }
    selector->data->bits.nth.a = nthA;
    selector->data->bits.nth.b = nthB;
    return true;
}

// a helper function for checking nth-arguments
static bool matchNth(const KatanaSelector * selector, int count)
{
    int nthAValue = selector->data->bits.nth.a;
    int nthBValue = selector->data->bits.nth.b;
    
    if (!nthAValue)
        return count == nthBValue;
    if (nthAValue > 0) {
        if (count < nthBValue)
            return false;
        return (count - nthBValue) % nthAValue == 0;
    }
    if (count > nthBValue)
        return false;
    return (nthBValue - count) % (-nthAValue) == 0;
}

SamuraiCSSPseudoId SamuraiCSSPseudoIdFromType(KatanaPseudoType type)
{
    switch (type) {
        case KatanaPseudoFirstLine:
            return FIRST_LINE;
        case KatanaPseudoFirstLetter:
            return FIRST_LETTER;
        case KatanaPseudoSelection:
            return SELECTION;
        case KatanaPseudoBefore:
            return BEFORE;
        case KatanaPseudoAfter:
            return AFTER;
        case KatanaPseudoBackdrop:
            return BACKDROP;
        case KatanaPseudoScrollbar:
            return SCROLLBAR;
        case KatanaPseudoScrollbarButton:
            return SCROLLBAR_BUTTON;
        case KatanaPseudoScrollbarCorner:
            return SCROLLBAR_CORNER;
        case KatanaPseudoScrollbarThumb:
            return SCROLLBAR_THUMB;
        case KatanaPseudoScrollbarTrack:
            return SCROLLBAR_TRACK;
        case KatanaPseudoScrollbarTrackPiece:
            return SCROLLBAR_TRACK_PIECE;
        case KatanaPseudoResizer:
            return RESIZER;
        case KatanaPseudoUnknown:
        case KatanaPseudoEmpty:
        case KatanaPseudoFirstChild:
        case KatanaPseudoFirstOfType:
        case KatanaPseudoLastChild:
        case KatanaPseudoLastOfType:
        case KatanaPseudoOnlyChild:
        case KatanaPseudoOnlyOfType:
        case KatanaPseudoNthChild:
        case KatanaPseudoNthOfType:
        case KatanaPseudoNthLastChild:
        case KatanaPseudoNthLastOfType:
        case KatanaPseudoLink:
        case KatanaPseudoVisited:
        case KatanaPseudoAny:
        case KatanaPseudoAnyLink:
        case KatanaPseudoAutofill:
        case KatanaPseudoHover:
        case KatanaPseudoDrag:
        case KatanaPseudoFocus:
        case KatanaPseudoActive:
        case KatanaPseudoChecked:
        case KatanaPseudoEnabled:
        case KatanaPseudoFullPageMedia:
        case KatanaPseudoDefault:
        case KatanaPseudoDisabled:
        case KatanaPseudoOptional:
        case KatanaPseudoRequired:
        case KatanaPseudoReadOnly:
        case KatanaPseudoReadWrite:
        case KatanaPseudoValid:
        case KatanaPseudoInvalid:
        case KatanaPseudoIndeterminate:
        case KatanaPseudoTarget:
        case KatanaPseudoLang:
        case KatanaPseudoNot:
        case KatanaPseudoRoot:
        case KatanaPseudoScope:
        case KatanaPseudoWindowInactive:
        case KatanaPseudoCornerPresent:
        case KatanaPseudoDecrement:
        case KatanaPseudoIncrement:
        case KatanaPseudoHorizontal:
        case KatanaPseudoVertical:
        case KatanaPseudoStart:
        case KatanaPseudoEnd:
        case KatanaPseudoDoubleButton:
        case KatanaPseudoSingleButton:
        case KatanaPseudoNoButton:
        case KatanaPseudoFirstPage:
        case KatanaPseudoLeftPage:
        case KatanaPseudoRightPage:
        case KatanaPseudoInRange:
        case KatanaPseudoOutOfRange:
        case KatanaPseudoWebKitCustomElement:
        case KatanaPseudoCue:
        case KatanaPseudoFutureCue:
        case KatanaPseudoPastCue:
        case KatanaPseudoUnresolved:
        case KatanaPseudoContent:
        case KatanaPseudoHost:
        case KatanaPseudoHostContext:
        case KatanaPseudoShadow:
        case KatanaPseudoFullScreen:
        case KatanaPseudoFullScreenDocument:
        case KatanaPseudoFullScreenAncestor:
        case KatanaPseudoSpatialNavigationFocus:
        case KatanaPseudoListBox:
            return NOPSEUDO;
        case KatanaPseudoNotParsed:
            // TODO: (@QFish) NSAssert(NO, @"Should not reached");
            return NOPSEUDO;
    }
    
    // TODO: (@QFish) NSAssert(NO, @"Should not reached");
    return NOPSEUDO;
}

// ----------------------------------
// Unit test
// ----------------------------------

#pragma mark -

#if __SAMURAI_TESTING__

TEST_CASE( WebCore, CSSSelectorChecker )

DESCRIBE( before )
{
}

DESCRIBE( after )
{
}

TEST_CASE_END

#endif	// #if __SAMURAI_TESTING__

#endif	// #if (TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR)

#import "_pragma_pop.h"
