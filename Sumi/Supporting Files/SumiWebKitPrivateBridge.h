#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WKUserScript (SumiWKPrivate)
- (instancetype)_initWithSource:(NSString *)source injectionTime:(WKUserScriptInjectionTime)injectionTime forMainFrameOnly:(BOOL)forMainFrameOnly includeMatchPatternStrings:(nullable NSArray<NSString *> *)includeMatchPatternStrings excludeMatchPatternStrings:(nullable NSArray<NSString *> *)excludeMatchPatternStrings associatedURL:(nullable NSURL *)associatedURL contentWorld:(nullable WKContentWorld *)contentWorld;
@end

typedef NS_ENUM(NSInteger, SumiWKUserStyleLevel) {
    SumiWKUserStyleLevelUser = 0,
    SumiWKUserStyleLevelAuthor = 1
};

@interface _WKUserStyleSheet : NSObject <NSCopying>
- (instancetype)initWithSource:(NSString *)source forWKWebView:(nullable WKWebView *)webView forMainFrameOnly:(BOOL)forMainFrameOnly includeMatchPatternStrings:(nullable NSArray<NSString *> *)includeMatchPatternStrings excludeMatchPatternStrings:(nullable NSArray<NSString *> *)excludeMatchPatternStrings baseURL:(nullable NSURL *)baseURL level:(SumiWKUserStyleLevel)level contentWorld:(nullable WKContentWorld *)contentWorld;
@end

@interface WKUserContentController (SumiWKPrivate)
- (void)_addUserStyleSheet:(_WKUserStyleSheet *)userStyleSheet;
- (void)_removeAllUserStyleSheetsAssociatedWithContentWorld:(WKContentWorld *)contentWorld;
- (void)_removeAllUserScriptsAssociatedWithContentWorld:(WKContentWorld *)contentWorld;
@end

static inline WKUserScript *SumiCreatePrivateUserScript(NSString *source, WKUserScriptInjectionTime injectionTime, BOOL forMainFrameOnly, NSArray<NSString *> * _Nullable includeMatchPatternStrings, NSArray<NSString *> * _Nullable excludeMatchPatternStrings, NSURL * _Nullable associatedURL, WKContentWorld * _Nullable contentWorld)
{
    return [[WKUserScript alloc] _initWithSource:source injectionTime:injectionTime forMainFrameOnly:forMainFrameOnly includeMatchPatternStrings:includeMatchPatternStrings excludeMatchPatternStrings:excludeMatchPatternStrings associatedURL:associatedURL contentWorld:contentWorld];
}

static inline _WKUserStyleSheet *SumiCreatePrivateUserStyleSheet(NSString *source, BOOL forMainFrameOnly, NSArray<NSString *> * _Nullable includeMatchPatternStrings, NSArray<NSString *> * _Nullable excludeMatchPatternStrings, NSURL * _Nullable baseURL, BOOL useUserLevel, WKContentWorld * _Nullable contentWorld)
{
    SumiWKUserStyleLevel level = useUserLevel ? SumiWKUserStyleLevelUser : SumiWKUserStyleLevelAuthor;
    return [[_WKUserStyleSheet alloc] initWithSource:source forWKWebView:nil forMainFrameOnly:forMainFrameOnly includeMatchPatternStrings:includeMatchPatternStrings excludeMatchPatternStrings:excludeMatchPatternStrings baseURL:baseURL level:level contentWorld:contentWorld];
}

static inline void SumiRemovePageWorldUserScripts(WKUserContentController *controller)
{
    [controller _removeAllUserScriptsAssociatedWithContentWorld:WKContentWorld.pageWorld];
}

static inline void SumiRemoveUserScriptsAssociatedWithContentWorld(WKUserContentController *controller, WKContentWorld *contentWorld)
{
    [controller _removeAllUserScriptsAssociatedWithContentWorld:contentWorld];
}

static inline void SumiRemovePageWorldUserStyleSheets(WKUserContentController *controller)
{
    [controller _removeAllUserStyleSheetsAssociatedWithContentWorld:WKContentWorld.pageWorld];
}

static inline void SumiRemoveUserStyleSheetsAssociatedWithContentWorld(WKUserContentController *controller, WKContentWorld *contentWorld)
{
    [controller _removeAllUserStyleSheetsAssociatedWithContentWorld:contentWorld];
}

static inline void SumiAddPrivateUserStyleSheet(WKUserContentController *controller, _WKUserStyleSheet *userStyleSheet)
{
    [controller _addUserStyleSheet:userStyleSheet];
}

static inline BOOL SumiSetWKPreferenceBool(WKPreferences *preferences, NSString *key, BOOL enabled)
{
    @try {
        [preferences setValue:@(enabled) forKey:key];
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
}

static inline void SumiSetAllowsPictureInPictureMediaPlayback(WKPreferences *preferences, BOOL enabled)
{
    SumiSetWKPreferenceBool(preferences, @"allowsPictureInPictureMediaPlayback", enabled);
}

static inline BOOL SumiSetVideoFullscreenRequiresElementFullscreen(WKPreferences *preferences, BOOL enabled)
{
    SEL setter = NSSelectorFromString(@"_setVideoFullscreenRequiresElementFullscreen:");
    if (![preferences respondsToSelector:setter])
        return NO;
    return SumiSetWKPreferenceBool(preferences, @"videoFullscreenRequiresElementFullscreen", enabled);
}

static inline NSView * _Nullable SumiWKWebViewFullScreenPlaceholderView(WKWebView *webView)
{
    SEL getter = NSSelectorFromString(@"_fullScreenPlaceholderView");
    if (![webView respondsToSelector:getter])
        return nil;

    @try {
        return [webView valueForKey:NSStringFromSelector(getter)];
    } @catch (NSException *exception) {
        return nil;
    }
}

@interface WKWebView (SumiWKNowPlayingPrivate)
@property (nonatomic, readonly, getter=_isPlayingAudio) BOOL _playingAudio;
@property (nonatomic, readonly) BOOL _canTogglePictureInPicture;
- (void)_nowPlayingMediaTitleAndArtist:(void (^)(NSString * _Nullable title, NSString * _Nullable artist))completionHandler;
- (void)_updateMediaPlaybackControlsManager;
- (void)_togglePictureInPicture;
@end

@interface _WKSessionState : NSObject
- (nullable instancetype)initWithData:(NSData *)data;
@property (nonatomic, readonly, nullable) NSData *data;
@end

@interface WKWebView (SumiWKSessionStatePrivate)
@property (nonatomic, readonly, nullable) _WKSessionState *_sessionState;
- (nullable WKNavigation *)_restoreSessionState:(_WKSessionState *)sessionState
                                    andNavigate:(BOOL)navigate;
@end

static inline NSData * _Nullable SumiWKSessionStateData(WKWebView *webView)
{
    @try {
        return webView._sessionState.data;
    } @catch (NSException *exception) {
        return nil;
    }
}

static inline WKNavigation * _Nullable SumiRestoreWKSessionState(
    WKWebView *webView,
    NSData *data
)
{
    @try {
        _WKSessionState *state = [[_WKSessionState alloc] initWithData:data];
        if (!state)
            return nil;
        return [webView _restoreSessionState:state andNavigate:YES];
    } @catch (NSException *exception) {
        return nil;
    }
}

NS_ASSUME_NONNULL_END
