/// Testimonials
///
/// Text testimonials with consent confirmation. No rating field (SRS explicitly excludes ratings).
///
/// Traceability: SRS WEB-10; PRD Section 6.5 (rating field intentionally omitted per Phase 0 decision)
///
/// Public API barrel. This feature owns lib/src/domain (entities, use
/// cases, repository interfaces), lib/src/data (DTOs, mappers, Firestore/
/// Storage/Functions repository implementations) and lib/src/presentation
/// (Flutter screens/widgets/state) per PRD Section 11.1. No other feature
/// package may import lib/src/** directly — only this barrel, and only
/// through core_contracts/design_system-typed public members.
///
/// Phase 0 scaffold: domain/data/presentation are intentionally empty
/// (.gitkeep only). Real exports land in the CMS Core / Public Website
/// implementation phases.
library;

/// Package identifier, useful for logging/diagnostics. Also keeps this
/// barrel a non-empty library so Phase 0 smoke tests have a real symbol
/// to import instead of an unused import.
const String featureModuleName = 'feature_testimonials';
