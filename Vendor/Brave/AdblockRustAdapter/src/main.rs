use adblock::content_blocking::{CbRule, CbRuleEquivalent, CbType};
use adblock::filters::network::NetworkFilterMaskHelper;
use adblock::lists::{parse_filter, FilterSet, ParseOptions, ParsedFilter, RuleTypes};
use serde::Serialize;
use std::collections::HashSet;
use std::convert::TryInto;
use std::io::{self, Read};

#[derive(Serialize)]
struct AdapterOutput {
    network: Vec<CbRule>,
    native_cosmetic_css: Vec<CbRule>,
    used_rules: Vec<String>,
    unsupported_or_ignored: Vec<AdapterDiagnostic>,
    enhanced_resource_candidates: Vec<EnhancedResourceCandidate>,
}

#[derive(Serialize)]
struct AdapterDiagnostic {
    rule: String,
    reason: String,
}

#[derive(Serialize, Clone, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum EnhancedResourceKind {
    Scriptlet,
    Redirect,
    NoopRedirect,
    ProceduralCosmetic,
}

#[derive(Serialize, Clone, PartialEq, Eq)]
struct EnhancedResourceCandidate {
    kind: EnhancedResourceKind,
    resource_name: String,
    parameters: Vec<String>,
    include_domains: Vec<String>,
    exclude_domains: Vec<String>,
    source_rule: String,
    diagnostic_source: String,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input)?;
    let rules: Vec<String> = input
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(ToOwned::to_owned)
        .collect();

    let network = compile_rules(&rules, RuleTypes::NetworkOnly)?;
    let cosmetic = compile_rules(&rules, RuleTypes::CosmeticOnly)?;
    let mut native_cosmetic_css = Vec::new();
    let mut unexpected_cosmetic_output = Vec::new();
    for rule in cosmetic.0 {
        if matches!(rule.action.typ, CbType::CssDisplayNone) {
            native_cosmetic_css.push(rule);
        } else {
            unexpected_cosmetic_output.push(AdapterDiagnostic {
                rule: "<adblock-rust cosmetic output>".to_string(),
                reason: format!(
                    "ignored non-native cosmetic content-blocking action: {:?}",
                    rule.action.typ
                ),
            });
        }
    }
    let used: HashSet<String> = network.1.iter().chain(cosmetic.1.iter()).cloned().collect();
    let mut unsupported_or_ignored = rules
        .iter()
        .filter(|rule| !rule.starts_with('!') && !used.contains(*rule))
        .map(|rule| AdapterDiagnostic {
            rule: rule.clone(),
            reason: unsupported_reason(rule),
        })
        .collect::<Vec<_>>();
    unsupported_or_ignored.append(&mut unexpected_cosmetic_output);
    let enhanced_resource_candidates = enhanced_resource_candidates(&rules);

    let output = AdapterOutput {
        network: network.0,
        native_cosmetic_css,
        used_rules: used.into_iter().collect(),
        unsupported_or_ignored,
        enhanced_resource_candidates,
    };
    println!("{}", serde_json::to_string_pretty(&output)?);
    Ok(())
}

fn enhanced_resource_candidates(rules: &[String]) -> Vec<EnhancedResourceCandidate> {
    let mut candidates = Vec::new();
    let mut seen = HashSet::new();
    for rule in rules {
        let Some(candidate) = enhanced_resource_candidate(rule) else {
            continue;
        };
        let key = format!(
            "{}:{}:{}:{}",
            candidate.kind_key(),
            candidate.resource_name,
            candidate.parameters.join("\u{1f}"),
            candidate.source_rule
        );
        if seen.insert(key) {
            candidates.push(candidate);
        }
    }
    candidates
}

fn enhanced_resource_candidate(rule: &str) -> Option<EnhancedResourceCandidate> {
    match parse_filter(rule, true, ParseOptions::default()) {
        Ok(ParsedFilter::Cosmetic(filter)) => {
            let args = filter.plain_css_selector()?;
            if !rule.contains("##+js(") {
                return procedural_candidate(rule);
            }
            let mut parsed_args = parse_scriptlet_args(args)?;
            if parsed_args.is_empty() {
                return None;
            }
            let resource_name = parsed_args.remove(0);
            let (include_domains, exclude_domains) = cosmetic_domains(rule);
            Some(EnhancedResourceCandidate {
                kind: EnhancedResourceKind::Scriptlet,
                resource_name,
                parameters: parsed_args,
                include_domains,
                exclude_domains,
                source_rule: rule.to_string(),
                diagnostic_source: "adblock-rust cosmetic parser".to_string(),
            })
        }
        Ok(ParsedFilter::Network(filter)) if filter.mask.is_redirect() => {
            let resource_name = filter.modifier_option?;
            let (include_domains, exclude_domains) = network_domains(rule);
            let lowered = resource_name.to_ascii_lowercase();
            let kind = if lowered.contains("noop")
                || lowered.contains("empty")
                || lowered.contains("blank")
            {
                EnhancedResourceKind::NoopRedirect
            } else {
                EnhancedResourceKind::Redirect
            };
            Some(EnhancedResourceCandidate {
                kind,
                resource_name,
                parameters: vec![],
                include_domains,
                exclude_domains,
                source_rule: rule.to_string(),
                diagnostic_source: "adblock-rust network parser".to_string(),
            })
        }
        _ => procedural_candidate(rule),
    }
}

impl EnhancedResourceCandidate {
    fn kind_key(&self) -> &'static str {
        match self.kind {
            EnhancedResourceKind::Scriptlet => "scriptlet",
            EnhancedResourceKind::Redirect => "redirect",
            EnhancedResourceKind::NoopRedirect => "noop_redirect",
            EnhancedResourceKind::ProceduralCosmetic => "procedural_cosmetic",
        }
    }
}

fn procedural_candidate(rule: &str) -> Option<EnhancedResourceCandidate> {
    if !(rule.contains("#?#") || rule.contains(":has(") || rule.contains(":has-text(")) {
        return None;
    }
    let (include_domains, exclude_domains) = cosmetic_domains(rule);
    Some(EnhancedResourceCandidate {
        kind: EnhancedResourceKind::ProceduralCosmetic,
        resource_name: "procedural-cosmetic".to_string(),
        parameters: vec![],
        include_domains,
        exclude_domains,
        source_rule: rule.to_string(),
        diagnostic_source: "adblock-rust cosmetic parser".to_string(),
    })
}

fn cosmetic_domains(rule: &str) -> (Vec<String>, Vec<String>) {
    let marker = if let Some(index) = rule.find("##") {
        Some(index)
    } else {
        rule.find("#?#")
    };
    let Some(index) = marker else {
        return (vec![], vec![]);
    };
    parse_domain_list(&rule[..index])
}

fn network_domains(rule: &str) -> (Vec<String>, Vec<String>) {
    let Some(options) = rule.split_once('$').map(|(_, options)| options) else {
        return (vec![], vec![]);
    };
    for option in options.split(',') {
        if let Some(domains) = option.strip_prefix("domain=") {
            return parse_domain_list(domains);
        }
    }
    (vec![], vec![])
}

fn parse_domain_list(value: &str) -> (Vec<String>, Vec<String>) {
    let mut include_domains = Vec::new();
    let mut exclude_domains = Vec::new();
    for item in value.split([',', '|']) {
        let domain = item.trim().trim_start_matches("||").trim_end_matches('^');
        if domain.is_empty() || domain == "*" {
            continue;
        }
        if let Some(excluded) = domain.strip_prefix('~') {
            if !excluded.is_empty() {
                exclude_domains.push(excluded.to_ascii_lowercase());
            }
        } else {
            include_domains.push(domain.to_ascii_lowercase());
        }
    }
    include_domains.sort();
    include_domains.dedup();
    exclude_domains.sort();
    exclude_domains.dedup();
    (include_domains, exclude_domains)
}

fn parse_scriptlet_args(args: &str) -> Option<Vec<String>> {
    let mut values = Vec::new();
    let mut current = String::new();
    let mut quote: Option<char> = None;
    let mut escaped = false;
    for ch in args.chars() {
        if escaped {
            current.push(ch);
            escaped = false;
            continue;
        }
        if ch == '\\' {
            escaped = true;
            continue;
        }
        if let Some(q) = quote {
            if ch == q {
                quote = None;
            } else {
                current.push(ch);
            }
            continue;
        }
        match ch {
            '\'' | '"' => quote = Some(ch),
            ',' => {
                values.push(current.trim().to_string());
                current.clear();
            }
            _ => current.push(ch),
        }
    }
    if quote.is_some() || escaped {
        return None;
    }
    values.push(current.trim().to_string());
    Some(values.into_iter().filter(|value| !value.is_empty()).collect())
}

fn unsupported_reason(rule: &str) -> String {
    match parse_filter(rule, true, ParseOptions::default()) {
        Ok(ParsedFilter::Network(filter)) => match TryInto::<CbRuleEquivalent>::try_into(filter) {
            Ok(_) => "ignored by selected content-blocking output groups".to_string(),
            Err(error) => {
                format!("unsupported by adblock-rust content-blocking conversion: {error:?}")
            }
        },
        Ok(ParsedFilter::Cosmetic(filter)) => match TryInto::<CbRule>::try_into(filter) {
            Ok(_) => "ignored by selected content-blocking output groups".to_string(),
            Err(error) => {
                format!("unsupported by adblock-rust content-blocking conversion: {error:?}")
            }
        },
        Err(error) => format!("ignored by adblock-rust parser: {error}"),
    }
}

fn compile_rules(
    rules: &[String],
    rule_types: RuleTypes,
) -> Result<(Vec<CbRule>, Vec<String>), Box<dyn std::error::Error>> {
    let mut set = FilterSet::new(true);
    set.add_filters(
        rules,
        ParseOptions {
            rule_types,
            ..ParseOptions::default()
        },
    );
    set.into_content_blocking()
        .map_err(|_| "adblock-rust content-blocking conversion requires debug FilterSet".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reports_scriptlet_as_unsupported_content_blocking_rule() {
        let reason = unsupported_reason("example.com##+js(sumi-future-scriptlet)");

        assert!(reason.contains("ScriptletInjectionsNotSupported"));
    }

    #[test]
    fn compiles_fixture_into_network_and_native_css_groups() {
        let rules = vec![
            "||ads.example.test^".to_string(),
            "##.ad-banner".to_string(),
            "example.test##.sponsored".to_string(),
            "example.test###sponsor.card[data-ad=\"1\"]".to_string(),
            "##+js(sumi-future-scriptlet)".to_string(),
        ];

        let network = compile_rules(&rules, RuleTypes::NetworkOnly).unwrap();
        let cosmetic = compile_rules(&rules, RuleTypes::CosmeticOnly).unwrap();

        assert_eq!(
            network
                .0
                .iter()
                .filter(|rule| matches!(rule.action.typ, CbType::Block))
                .count(),
            1
        );
        assert_eq!(
            cosmetic
                .0
                .iter()
                .filter(|rule| matches!(rule.action.typ, CbType::CssDisplayNone))
                .count(),
            3
        );
        assert!(network
            .0
            .iter()
            .any(|rule| matches!(rule.action.typ, CbType::IgnorePreviousRules)));
    }

    #[test]
    fn adapter_output_keeps_only_native_css_and_reports_scriptlets() {
        let rules = vec![
            "||ads.example.test^".to_string(),
            "##.ad-banner".to_string(),
            "example.test##.sponsored".to_string(),
            "example.test###sponsor.card[data-ad=\"1\"]".to_string(),
            "##+js(sumi-future-scriptlet)".to_string(),
        ];
        let network = compile_rules(&rules, RuleTypes::NetworkOnly).unwrap();
        let cosmetic = compile_rules(&rules, RuleTypes::CosmeticOnly).unwrap();
        let used: HashSet<String> = network.1.iter().chain(cosmetic.1.iter()).cloned().collect();
        let native_cosmetic_css: Vec<CbRule> = cosmetic
            .0
            .into_iter()
            .filter(|rule| matches!(rule.action.typ, CbType::CssDisplayNone))
            .collect();
        let unsupported_or_ignored: Vec<AdapterDiagnostic> = rules
            .iter()
            .filter(|rule| !rule.starts_with('!') && !used.contains(*rule))
            .map(|rule| AdapterDiagnostic {
                rule: rule.clone(),
                reason: unsupported_reason(rule),
            })
            .collect();

        assert!(native_cosmetic_css
            .iter()
            .all(|rule| matches!(rule.action.typ, CbType::CssDisplayNone)));
        assert_eq!(native_cosmetic_css.len(), 3);
        assert_eq!(unsupported_or_ignored.len(), 1);
        assert!(unsupported_or_ignored[0]
            .reason
            .to_ascii_lowercase()
            .contains("script"));
    }

    #[test]
    fn extracts_scriptlet_resource_candidates_with_domains_and_arguments() {
        let rules = vec![
            "example.com,~cdn.example.com##+js(sumi-hide, .ad-slot)".to_string(),
            "other.example##.native".to_string(),
        ];

        let candidates = enhanced_resource_candidates(&rules);

        assert_eq!(candidates.len(), 1);
        assert!(matches!(candidates[0].kind, EnhancedResourceKind::Scriptlet));
        assert_eq!(candidates[0].resource_name, "sumi-hide");
        assert_eq!(candidates[0].parameters, vec![".ad-slot"]);
        assert_eq!(candidates[0].include_domains, vec!["example.com"]);
        assert_eq!(candidates[0].exclude_domains, vec!["cdn.example.com"]);
        assert!(candidates[0].diagnostic_source.contains("adblock-rust"));
    }

    #[test]
    fn extracts_redirect_resource_candidates_from_adblock_rust_parse() {
        let rules = vec![
            "||cdn.example/script.js$script,redirect=noopjs,domain=example.com|~static.example.com"
                .to_string(),
        ];

        let candidates = enhanced_resource_candidates(&rules);

        assert_eq!(candidates.len(), 1);
        assert!(matches!(candidates[0].kind, EnhancedResourceKind::NoopRedirect));
        assert_eq!(candidates[0].resource_name, "noopjs");
        assert_eq!(candidates[0].include_domains, vec!["example.com"]);
        assert_eq!(candidates[0].exclude_domains, vec!["static.example.com"]);
    }
}
