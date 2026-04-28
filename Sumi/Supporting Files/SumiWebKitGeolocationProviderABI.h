//
//  SumiWebKitGeolocationProviderABI.h
//  Sumi
//
//  Closely adapted private WebKit ABI surface from DuckDuckGo Apple Browser's
//  WKGeolocationProvider.h, which is licensed under the Apache License,
//  Version 2.0. See docs/permissions/LICENSE_NOTES.md for source and notice
//  details.
//
//  Original DuckDuckGo notice:
//  Copyright © 2021 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

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
