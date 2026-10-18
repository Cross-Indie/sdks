using UnrealBuildTool;

public class CrossIndie : ModuleRules
{
    public CrossIndie(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = ModuleRules.PCHUsageMode.UseExplicitOrSharedPCHs;

        PublicDependencyModuleNames.AddRange(new string[]
        {
            "Core", "CoreUObject", "Engine"
        });

        PrivateDependencyModuleNames.AddRange(new string[]
        {
            "HTTP", "Json", "JsonUtilities"
        });
    }
}
