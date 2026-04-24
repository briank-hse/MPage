# Corpus QA Report

Generated: 2026-04-24 12:15

## Overview

| Metric | Count |
| --- | --- |
| Total documents | 2,874 |
| Total chunks | 11,957 |
| Chunks with any enrichment | 11,957 (100.0%) |

## Platform Breakdown

**Documents:**

- `forum`: 839 (29.2%)
- `unknown`: 97 (3.4%)
- `wiki`: 1,938 (67.4%)

**Chunks:**

- `forum`: 6,250 (52.3%)
- `unknown`: 377 (3.2%)
- `wiki`: 5,330 (44.6%)

## Processing Cache Status

- `duplicate_hash`: 219
- `duplicate_url`: 338
- `processed`: 2,874

## Forum Duplication Check (F1)

- Forum docs with comments: 736
- Likely-duplicated docs: 11 — **ISSUE**
- Examples: forum_230674, forum_149837, forum_224107, forum_267362, forum_267004

## Enrichment Field Coverage (F2)


### Chunks

| Field | Key Present | Meaningful Value | Coverage % |
| --- | --- | --- | --- |
| `product_area` | 11,957 | 9,196 | 76.9% [!] |
| `integration_pattern` | 11,957 | 11,957 | 100.0% |
| `output_pattern` | 11,957 | 169 | 1.4% [x] |
| `runtime_context` | 11,957 | 291 | 2.4% [x] |
| `artifact_type` | 11,957 | 11,957 | 100.0% |
| `search_terms` | 11,957 | 11,956 | 100.0% |
| `exact_terms` | 11,957 | 6,213 | 52.0% [!] |
| `topic_tags` | 11,957 | 6,652 | 55.6% [!] |
| `contains_code` | 11,957 | 3,178 | 26.6% [x] |
| `code_languages` | 11,957 | 2,234 | 18.7% [x] |

### Documents

| Field | Key Present | Meaningful Value | Coverage % |
| --- | --- | --- | --- |
| `product_area` | 2,874 | 2,359 | 82.1% [!] |
| `integration_pattern` | 2,874 | 2,874 | 100.0% |
| `output_pattern` | 2,874 | 85 | 3.0% [x] |
| `runtime_context` | 2,874 | 104 | 3.6% [x] |
| `artifact_type` | 2,874 | 2,874 | 100.0% |
| `search_terms` | 2,874 | 2,873 | 100.0% |
| `exact_terms` | 2,874 | 1,984 | 69.0% [!] |
| `topic_tags` | 2,874 | 2,174 | 75.6% [!] |
| `contains_code` | 2,874 | 996 | 34.7% [x] |
| `code_languages` | 2,874 | 558 | 19.4% [x] |

## Unknown-Platform Documents

Count: 97

Examples:
- **2013 Software Intern Hackfest |
Engineering Health** — `2013_Software_Intern_Hackfest_Engineering_Health__25ae5554cd.html` — `https://engineering.cerner.com/blog/software-intern-hackfest`
- **2^5 Coding Competition 2017: 32 lines or less |
Engineering Health** — `2_5_Coding_Competition_2017_32_lines_or_less_Engineering_Health__a3c9bb7b9e.html` — `https://engineering.cerner.com/blog/2-to-the-5th-coding-competition-2017`
- **2^5 Coding Competition 2018 |
Engineering Health** — `2_5_Coding_Competition_2018_Engineering_Health__207db03f7f.html` — `https://engineering.cerner.com/blog/2-to-the-5th-coding-competition-2018`
- **Abbreviating+Table+Names+Using+Discern+Explorer** — `Abbreviating+Table+Names+Using+Discern+Explorer.html` — ``
- **Alan and Grace: An Origin Story |
Engineering Health** — `Alan_and_Grace_An_Origin_Story_Engineering_Health__e87838b730.html` — `https://engineering.cerner.com/blog/alan-and-grace-an-origin-story`
- **Announcing Bunsen: FHIR Data with Apache Spark |
Engineering Health** — `Announcing_Bunsen_FHIR_Data_with_Apache_Spark_Engineering_Health__572741f89a.html` — `https://engineering.cerner.com/blog/announcing-bunsen-fhir-data-with-apache-spark`
- **Automated Deployment with Apache Kafka |
Engineering Health** — `Automated_Deployment_with_Apache_Kafka_Engineering_Health__0576d40ccd.html` — `https://engineering.cerner.com/blog/automated-deployment-with-apache-kafka`
- **Beadledom - Simple Java framework for building REST APIs |
Engineering Health** — `Beadledom_-_Simple_Java_framework_for_building_REST_APIs_Engineering_Health__c589401edb.html` — `https://engineering.cerner.com/blog/beadledom-simple-java-framework-for-building-rest-apis`

## Size Outliers

**Largest documents (by word count):**

- `forum_224428`: 30,083 words — Rev 8 Upgrade Questions
- `forum_182451`: 30,083 words — Rev 8 Upgrade Questions
- `forum_224107`: 29,085 words — Question about data string lengths
- `wiki_c08793e4ee0344e9`: 20,328 words — Configure Clinical Document Generator
- `wiki_5485cff5c5c616fa`: 20,158 words — CommunityWorks Reporting DA2 Metadata, Queries, Report Updates - Commu

**Small chunks (<20 words)**: 245
