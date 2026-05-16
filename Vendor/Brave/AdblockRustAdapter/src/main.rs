use adblock::content_blocking::{CbRule, CbRuleEquivalent, CbType};
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
}

#[derive(Serialize)]
struct AdapterDiagnostic {
    rule: String,
    reason: String,
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

    let output = AdapterOutput {
        network: network.0,
        native_cosmetic_css,
        used_rules: used.into_iter().collect(),
        unsupported_or_ignored,
    };
    println!("{}", serde_json::to_string_pretty(&output)?);
    Ok(())
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
}
