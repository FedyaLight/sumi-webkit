//
//  SumiDomainCompatibility.swift
//  Sumi
//
//  Re-exports SumiDomain into the app module during the SPM peel so call sites
//  keep resolving Foundation domain types without per-file import churn.
//

@_exported import SumiDomain
