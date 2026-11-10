# Algeria transport-law review — MITHAQ release blocker

Research date: 10 November 2026. This is a product-risk note, not a legal opinion.

## Findings that affect the launch model

1. The taxi regime is regulated separately. Executive Decree 12-230 (24 May 2012) regulates taxi services. Executive Decree 16-82 (1 March 2016) amended it; Article 9 states that access to operating a taxi service is subject to an operating authorization issued by the Director of Transport of the relevant wilaya. The Official Journal publication is the primary source:
   - https://www.joradp.dz/FTP/jo-francais/2016/F2016013.pdf
   - Ministry of Commerce listing for the 2016 taxi specifications / cahier des charges: https://www.commerce.gov.dz/reglementation/arrete-du-14-aout-2016-cahier-des-charges

2. A separate VTC / digitally booked chauffeured-car model has been discussed. The Competition Council published a contribution to a draft executive decree for VTC activity via a digital platform in December 2023 / February 2024:
   - https://www.conseil-concurrence.dz/?p=9901
   A contribution to a draft is not itself an enacted regulation.

3. A 9 April 2026 report quoting the Ministry's Director of Road Transport and Logistics says VTC activity was then being carried on without official authorization from the Ministry of Transport and that the authorities were still considering a regulatory framework:
   - https://algerie-eco.com/2026/04/09/nouveau-code-de-la-route-tarification-des-taxis-vtc-un-responsable-du-secteur-des-transports-sexprime/
   This is a reported statement, not a substitute for checking the latest Journal Officiel and obtaining written advice from the relevant authorities.

4. The Ministry of Commerce lists Executive Decree 02-448 on maximum taxi passenger fares:
   - https://www.commerce.gov.dz/reglementation/decret-executif-n-deg-02-448
   A VTC fare model should not simply assume that taxi tariff rules automatically apply or do not apply; this needs a legal determination for the actual operating structure.

5. In August 2026, a report quoting the Gendarmerie Nationale's Tariki communication reiterated that public passenger-transport operators must hold the specific authorization from the wilaya transport directorate, and described penalties under Law 01-13 for unauthorized public passenger transport:
   - https://elkhabar.com.dz/fr/societe/transport-public-de-personnes-la-gendarmerie-rappelle-l-obligation-de-detenir-une-autorisation-264467
   This is a reported official reminder about public passenger transport generally; obtain a legal determination of whether and how it applies to the exact MITHAQ test and operating model.

## Product decisions taken

- MITHAQ remains a closed software test, not an operating transport company.
- Driver/vehicle approval inside the admin UI is only a test-platform flag. It is not a transport permit, professional driver card, vehicle authorization, insurance approval, or legal clearance.
- No paid passenger trips, public driver recruitment, public launch, or commercial fare collection until the company/operator model and required permits are confirmed in writing.
- Before a field test, obtain advice from the Directorate of Transport in the intended wilaya and qualified Algerian counsel on whether even a non-commercial real-world passenger test is permitted, and what insurance applies.
- Keep the first functional test non-commercial and controlled. If legal permission for carrying a passenger is unclear, test request/dispatch/status/GPS/PIN flows with the vehicles stationary or on private property instead.

## Required legal work before public pilot

- Confirm the correct legal form and registered activity for the platform operator.
- Obtain a written determination of the rules applicable to app-booked chauffeur services (VTC) versus licensed taxi services.
- Confirm operator, driver, and vehicle authorizations with the Directorate of Transport for the launch wilaya.
- Confirm professional liability / passenger coverage, vehicle insurance, and driver coverage for paid and test journeys.
- Confirm applicable fare rules, tax/accounting obligations, contracts, cancellation/refund terms, and consumer protection duties.
- Confirm personal-data processing obligations for account, GPS, identity, trip, and incident data.
- Define staffed emergency and incident response before any public trips.

Do not interpret a database flag or a test ride as evidence of legal eligibility.
