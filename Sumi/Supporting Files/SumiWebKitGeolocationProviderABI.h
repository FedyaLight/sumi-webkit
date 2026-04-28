#import <stdbool.h>

// Private WebKit C geolocation provider ABI. This mirrors the WebKit
// WKGeolocationProviderBase/V1 layout so Swift code can install callbacks while
// keeping symbol use isolated behind SumiGeolocationProvider.

typedef void (*SumiWKGeolocationProviderStartUpdatingCallback)(const void * _Nullable geolocationManager, const void * _Nullable clientInfo);
typedef void (*SumiWKGeolocationProviderStopUpdatingCallback)(const void * _Nullable geolocationManager, const void * _Nullable clientInfo);
typedef void (*SumiWKGeolocationProviderSetEnableHighAccuracyCallback)(const void * _Nullable geolocationManager, bool enabled, const void * _Nullable clientInfo);

typedef struct SumiWKGeolocationProviderBase {
    int version;
    const void * _Nullable clientInfo;
} SumiWKGeolocationProviderBase;

typedef struct SumiWKGeolocationProviderV1 {
    SumiWKGeolocationProviderBase base;
    SumiWKGeolocationProviderStartUpdatingCallback _Nullable startUpdating;
    SumiWKGeolocationProviderStopUpdatingCallback _Nullable stopUpdating;
    SumiWKGeolocationProviderSetEnableHighAccuracyCallback _Nullable setEnableHighAccuracy;
} SumiWKGeolocationProviderV1;
