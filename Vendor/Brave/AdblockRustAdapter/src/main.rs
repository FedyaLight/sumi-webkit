use adblock::content_blocking::{CbRule, CbType};
use adblock::lists::{FilterSet, ParseOptions, RuleTypes};
use serde::Serialize;
use std::collections::HashSet;
use std::io::{self, Read};

#[derive(Serialize)]
struct AdapterOutput {
    network: Vec<CbRule>,
    native_cosmetic_css: Vec<CbRule>,
    used_rules: Vec<String>,
    unsupported_or_ignored: Vec<String>,
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
    let used: HashSet<String> = network
        .1
        .iter()
        .chain(cosmetic.1.iter())
        .cloned()
        .collect();
    let unsupported_or_ignored = rules
        .iter()
        .filter(|rule| !rule.starts_with('!') && !used.contains(*rule))
        .cloned()
        .collect();

    let output = AdapterOutput {
        network: network.0,
        native_cosmetic_css: cosmetic
            .0
            .into_iter()
            .filter(|rule| matches!(rule.action.typ, CbType::CssDisplayNone))
            .collect(),
        used_rules: used.into_iter().collect(),
        unsupported_or_ignored,
    };
    println!("{}", serde_json::to_string_pretty(&output)?);
    Ok(())
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

