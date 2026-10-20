// CrossIndie cross-promotion banner component for Unreal Engine.
//
// This ActorComponent handles fetching an ad, enforcing the server-mandated
// minimum display time (only while the app is focused) and reporting
// impressions / clicks. Rendering is left to your UMG: bind OnAdLoaded to show
// the title / description / banner image however your UI prefers.
#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "Interfaces/IHttpRequest.h"
#include "CrossIndieBannerComponent.generated.h"

DECLARE_DYNAMIC_MULTICAST_DELEGATE_FourParams(
    FCrossIndieAdLoaded,
    const FString&, Name,
    const FString&, Description,
    const FString&, BannerImageUrl,
    const FString&, TargetUrl);

DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(
    FCrossIndieAdFailed, const FString&, Reason);

UCLASS(ClassGroup = (CrossIndie), meta = (BlueprintSpawnableComponent))
class CROSSINDIE_API UCrossIndieBannerComponent : public UActorComponent
{
    GENERATED_BODY()

public:
    UCrossIndieBannerComponent();

    /** Base URL of your CrossIndie backend, e.g. https://api.crossindie.com */
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "CrossIndie")
    FString ApiBase = TEXT("http://localhost:8000");

    /** This game's app id from the CrossIndie dashboard. */
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "CrossIndie")
    FString AppId;

    /** Category pool: game / web_tool / saas / mobile_app. */
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "CrossIndie")
    FString Category = TEXT("game");

    /** Fetch an ad automatically on BeginPlay. */
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "CrossIndie")
    bool bAutoLoad = true;

    /** Fired when an ad is ready to display. */
    UPROPERTY(BlueprintAssignable, Category = "CrossIndie")
    FCrossIndieAdLoaded OnAdLoaded;

    /** Fired when no ad is available or a request fails. */
    UPROPERTY(BlueprintAssignable, Category = "CrossIndie")
    FCrossIndieAdFailed OnAdFailed;

    /** Request a fresh ad from the network. */
    UFUNCTION(BlueprintCallable, Category = "CrossIndie")
    void LoadAd();

    /** Call when the player clicks the banner: opens the store URL + tracks. */
    UFUNCTION(BlueprintCallable, Category = "CrossIndie")
    void HandleClick();

protected:
    virtual void BeginPlay() override;
    virtual void TickComponent(float DeltaTime, ELevelTick TickType,
                               FActorComponentTickFunction* ThisTickFunction) override;

private:
    FString TrackingToken;
    FString TargetUrl;
    int32 MinDisplayMs = 1500;

    bool bImpressionSent = false;
    bool bClickSent = false;
    bool bCounting = false;
    float VisibleMs = 0.f;

    FString BaseUrl() const;
    void OnFetchResponse(FHttpRequestPtr Req, FHttpResponsePtr Res, bool bOk);
    void Track(const FString& EventType);
};
