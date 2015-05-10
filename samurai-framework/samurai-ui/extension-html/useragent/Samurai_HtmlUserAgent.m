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

#import "Samurai_HtmlUserAgent.h"

#import "_pragma_push.h"

#if (TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR)

#import "Samurai_HtmlRenderObject.h"
#import "Samurai_HtmlRenderObjectContainer.h"
#import "Samurai_HtmlRenderObjectElement.h"
#import "Samurai_HtmlRenderObjectText.h"
#import "Samurai_HtmlRenderObjectViewport.h"

#import "Samurai_HtmlStyle.h"
#import "Samurai_HtmlMediaQuery.h"

#import "Samurai_CSSParser.h"
#import "Samurai_CSSStyleSheet.h"

// ----------------------------------
// Source code
// ----------------------------------

#pragma mark -

@implementation SamuraiHtmlUserAgent

@def_prop_strong( UIFont *,				defaultFont );
@def_prop_strong( NSMutableArray *,		defaultStyleSheets );
@def_prop_strong( NSMutableArray *,		defaultCSSInherition );

@def_singleton( SamuraiHtmlUserAgent )

- (id)init
{
	self = [super init];
	if ( self )
	{
		self.defaultFont = [UIFont systemFontOfSize:16.0f];

		[self loadStyleSheets];
		[self loadCSSInheration];
	}
	return self;
}

- (void)dealloc
{
	self.defaultFont = nil;
	self.defaultStyleSheets = nil;
	self.defaultCSSInherition = nil;
}

- (void)loadStyleSheets
{
	self.defaultStyleSheets = [NSMutableArray array];
	
	SamuraiCSSStyleSheet * styleSheet;
 
	styleSheet = [SamuraiCSSStyleSheet resourceAtPath:@"html.css"];
	
	if ( styleSheet && [styleSheet parse] )
	{
		[self.defaultStyleSheets addObject:styleSheet];
	}

	styleSheet = [SamuraiCSSStyleSheet resourceAtPath:@"html+ios.css"];
	
	if ( styleSheet && [styleSheet parse] )
	{
		[self.defaultStyleSheets addObject:styleSheet];
	}
}

- (void)loadCSSInheration
{
	self.defaultCSSInherition = [NSMutableArray arrayWithObjects:

		@"border-collapse",
		@"border-spacing",
		@"caption-side",
		
		@"cursor",
		
		@"direction",
		@"text-align",
		@"text-indent",
		@"text-transform",
								 
		@"empty-cells",
		
		@"color",
		@"font",
		@"font-family",
		@"font-size",
		@"font-style",
		@"font-variant",
		@"font-weight",
		@"letter-spacing",
		@"line-height",
		@"word-spacing",
		@"word-wrap",
		
		@"list-style",
		@"list-style-image",
		@"list-style-position",
		@"list-style-type",
		
		@"orphans",
		@"widows",
		
		@"quotes",
		
		@"azimuth",
		@"elevation",
		@"pitch-range",
		@"pitch",
		@"richness",
		@"speak-header",
		@"speak-numeral",
		@"speak-punctuation",
		@"speak",
		@"speech-rate",
		@"stress",
		@"voice-family",
		@"volume",
		
		@"visibility",
		
		@"whitespace",
		
	nil];
}

@end

// ----------------------------------
// Unit test
// ----------------------------------

#pragma mark -

#if __SAMURAI_TESTING__

TEST_CASE( UI, HtmlUserAgent )

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
