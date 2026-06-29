from typing import Dict

def analyze_dependency(dependency_data: Dict) -> Dict:
    """
    Input
    -----
    {
        "dependencyName": "org.apache.logging.log4j:log4j-core",
        "current_version": "2.14.1",
        "fixed_versions": [
            "2.15.0",
            "2.16.0",
            "2.17.0"
        ]
    }

    Output
    ------
    {
        "dependencyName": "org.apache.logging.log4j:log4j-core",
        "non_breaking_changes": [
            "2.15.0",
            "2.17.0"
        ]
    }
    """

    dependency_name = dependency_data["dependencyName"]
    current_version = dependency_data["current_version"]

    non_breaking_changes = []

    for fixed_version in dependency_data["fixed_versions"]:

        request = {
            "dependencyName": dependency_name,
            "current_version": current_version,
            "fixed_version": fixed_version
        }

        if is_version_non_breaking(request):
            non_breaking_changes.append(fixed_version)

    return {
        "dependencyName": dependency_name,
        "non_breaking_changes": non_breaking_changes
    }


def is_version_non_breaking(version_request: Dict) -> bool:

    enriched_context = gather_context(version_request)

    llm_result = llm_breaking_change_decision(enriched_context)

    scores = [
        llm_result["semantic_version_score"],
        llm_result["api_compatibility_score"],
        llm_result["binary_compatibility_score"],
        llm_result["source_compatibility_score"],
        llm_result["configuration_change_score"],
        llm_result["runtime_behavior_score"],
        llm_result["migration_effort_score"],
        llm_result["dependency_conflict_score"],
        llm_result["repository_usage_score"],
        llm_result["release_notes_score"],
    ]

    # -----------------------------------------------------
    # Business Rules
    # -----------------------------------------------------

    # Any critical factor is too risky.
    if min(scores) < 5:
        return False

    # LLM itself believes the upgrade is breaking.
    if not llm_result["non_breaking"]:
        return False

    # Overall confidence too low.
    if llm_result["overall_score"] < 80:
        return False

    return True




def gather_context(version_request: Dict) -> Dict:
    """
    Placeholder function.

    Later this function can collect:

    • Changelog
    • Release Notes
    • GitHub Releases
    • Migration Guide
    • API Differences
    • Binary Compatibility Report
    • Semantic Version Difference
    • Repository Dependency Usage
    • Imports Used
    • Public API Usage
    • Transitive Dependency Changes
    • etc.
    """

    return version_request



def llm_breaking_change_decision(context: Dict) -> Dict:
    """
    Sends all collected information to an LLM.

    The LLM evaluates the upgrade on multiple factors
    and assigns scores.

    Returns a structured JSON.
    """

    prompt = f"""
You are an expert software dependency compatibility analyzer.

Analyze whether upgrading the following dependency is likely to introduce
breaking changes.

Dependency Information

{context}

Evaluate the upgrade on the following factors.

1. Semantic Version Compatibility
2. Public API Compatibility
3. Binary Compatibility
4. Source Compatibility
5. Configuration Compatibility
6. Runtime Behavior Compatibility
7. Migration Effort Required
8. Dependency Conflict Risk
9. Repository Usage Compatibility
10. Release Notes / Documented Breaking Changes

For each factor assign a score from 0 to 10.

Scoring Guide

10 = Completely Safe
8-9 = Very Low Risk
5-7 = Moderate Risk
0-4 = High Breaking Risk

Then calculate an overall_score from 0 to 100.

Finally decide whether the upgrade appears non_breaking.

Return ONLY JSON in the following format.

{{
    "semantic_version_score": 0,
    "api_compatibility_score": 0,
    "binary_compatibility_score": 0,
    "source_compatibility_score": 0,
    "configuration_change_score": 0,
    "runtime_behavior_score": 0,
    "migration_effort_score": 0,
    "dependency_conflict_score": 0,
    "repository_usage_score": 0,
    "release_notes_score": 0,
    "overall_score": 0,
    "non_breaking": false,
    "reason": ""
}}

Return ONLY valid JSON.
"""

    # ==========================================================
    # Replace the below block with your preferred LLM call.
    #
    # Example:
    #
    # response = llm.invoke(prompt)
    # result = json.loads(response.content)
    # return result
    #
    # ==========================================================

    return {
        "semantic_version_score": 9,
        "api_compatibility_score": 8,
        "binary_compatibility_score": 10,
        "source_compatibility_score": 8,
        "configuration_change_score": 8,
        "runtime_behavior_score": 9,
        "migration_effort_score": 8,
        "dependency_conflict_score": 9,
        "repository_usage_score": 9,
        "release_notes_score": 9,
        "overall_score": 87,
        "non_breaking": True,
        "reason": "No significant breaking changes detected."
    }


# ==============================================================================
# Example
# ==============================================================================

if __name__ == "__main__":

    dependency = {
        "dependencyName": "org.apache.logging.log4j:log4j-core",
        "current_version": "2.14.1",
        "fixed_versions": [
            "2.15.0",
            "2.16.0",
            "2.17.0"
        ]
    }

    result = analyze_dependency(dependency)

    print(result)
