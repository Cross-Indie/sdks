#include "CrossIndieBannerComponent.h"

#include "HttpModule.h"
#include "Interfaces/IHttpResponse.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Misc/App.h"
#include "GenericPlatform/GenericPlatformHttp.h"

UCrossIndieBannerComponent::UCrossIndieBannerComponent()
{
    PrimaryComponentTick.bCanEverTick = true;
}

FString UCrossIndieBannerComponent::BaseUrl() const
{
    FString Base = ApiBase;
    while (Base.EndsWith(TEXT("/")))
    {
        Base.LeftChopInline(1);
    }
    return Base;
}

void UCrossIndieBannerComponent::BeginPlay()
{
    Super::BeginPlay();
    if (bAutoLoad)
    {
        LoadAd();
    }
}

void UCrossIndieBannerComponent::LoadAd()
{
    if (AppId.IsEmpty())
    {
        OnAdFailed.Broadcast(TEXT("AppId is not set"));
        return;
    }

    bImpressionSent = false;
    bClickSent = false;
    bCounting = false;
    VisibleMs = 0.f;

    const FString Url = FString::Printf(
        TEXT("%s/api/v1/ad/fetch?app_id=%s&category=%s"),
        *BaseUrl(),
        *FGenericPlatformHttp::UrlEncode(AppId),
        *FGenericPlatformHttp::UrlEncode(Category));

    const TSharedRef<IHttpRequest, ESPMode::ThreadSafe> Req =
        FHttpModule::Get().CreateRequest();
    Req->SetURL(Url);
    Req->SetVerb(TEXT("GET"));
    Req->SetHeader(TEXT("Accept"), TEXT("application/json"));
    Req->OnProcessRequestComplete().BindUObject(
        this, &UCrossIndieBannerComponent::OnFetchResponse);
    Req->ProcessRequest();
}

void UCrossIndieBannerComponent::OnFetchResponse(
    FHttpRequestPtr Req, FHttpResponsePtr Res, bool bOk)
{
    if (!bOk || !Res.IsValid())
    {
        OnAdFailed.Broadcast(TEXT("fetch request failed"));
        return;
    }

    const int32 Code = Res->GetResponseCode();
    if (Code == 204)
    {
        OnAdFailed.Broadcast(TEXT("no eligible ads available"));
        return;
    }
    if (Code != 200)
    {
        OnAdFailed.Broadcast(FString::Printf(TEXT("fetch failed (%d)"), Code));
        return;
    }

    TSharedPtr<FJsonObject> Json;
    const TSharedRef<TJsonReader<>> Reader =
        TJsonReaderFactory<>::Create(Res->GetContentAsString());
    if (!FJsonSerializer::Deserialize(Reader, Json) || !Json.IsValid())
    {
        OnAdFailed.Broadcast(TEXT("invalid ad payload"));
        return;
    }

    TrackingToken = Json->GetStringField(TEXT("tracking_token"));
    TargetUrl = Json->GetStringField(TEXT("target_url"));
    MinDisplayMs = Json->HasField(TEXT("min_display_ms"))
                       ? Json->GetIntegerField(TEXT("min_display_ms"))
                       : 1500;

    OnAdLoaded.Broadcast(
        Json->GetStringField(TEXT("name")),
        Json->GetStringField(TEXT("description")),
        Json->GetStringField(TEXT("banner_image_url")),
        TargetUrl);

    bCounting = true; // start accruing display time
}

void UCrossIndieBannerComponent::TickComponent(
    float DeltaTime, ELevelTick TickType,
    FActorComponentTickFunction* ThisTickFunction)
{
    Super::TickComponent(DeltaTime, TickType, ThisTickFunction);

    if (!bCounting || bImpressionSent)
    {
        return;
    }
    // Only accrue time while the application window is focused.
    if (!FApp::HasFocus())
    {
        return;
    }

    VisibleMs += DeltaTime * 1000.f;
    if (VisibleMs >= static_cast<float>(MinDisplayMs))
    {
        bCounting = false;
        Track(TEXT("impression"));
    }
}

void UCrossIndieBannerComponent::HandleClick()
{
    if (TargetUrl.IsEmpty())
    {
        return;
    }
    FPlatformProcess::LaunchURL(*TargetUrl, nullptr, nullptr);
    if (!bClickSent)
    {
        Track(TEXT("click"));
    }
}

void UCrossIndieBannerComponent::Track(const FString& EventType)
{
    if (TrackingToken.IsEmpty())
    {
        return;
    }
    if (EventType == TEXT("impression")) bImpressionSent = true;
    if (EventType == TEXT("click")) bClickSent = true;

    const FString Body = FString::Printf(
        TEXT("{\"tracking_token\":\"%s\",\"event_type\":\"%s\"}"),
        *TrackingToken, *EventType);

    const TSharedRef<IHttpRequest, ESPMode::ThreadSafe> Req =
        FHttpModule::Get().CreateRequest();
    Req->SetURL(FString::Printf(TEXT("%s/api/v1/ad/track"), *BaseUrl()));
    Req->SetVerb(TEXT("POST"));
    Req->SetHeader(TEXT("Content-Type"), TEXT("application/json"));
    Req->SetContentAsString(Body);
    Req->ProcessRequest();
}
