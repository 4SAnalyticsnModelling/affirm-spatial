![AFFIRM Spatial logo](resource/affirm_logo.png)

# AFFIRM Spatial

**AFFIRM Spatial** is a standalone batch runner for the Alberta Farm Fertilizer Information Recommendation Manager nitrogen model. It is designed for fast scenario runs from text input files and writes tab-delimited model results that can be opened in spreadsheet, GIS, database, or scripting workflows.

AFFIRM has multiple public versions:

- [AFFIRM v3.0](https://www.alberta.ca/alberta-farm-fertilizer-information-and-recommendation-manager), the production Government of Alberta tool.
- [AFFIRM Lite](https://www.4sanalyticsnmodelling.com/affirm-lite/), a web application of a simplified version of AFFIRM v3.0.
- **AFFIRM Spatial**, this repository, a downloadable command-line batch tool for larger spatial or scenario-based workflows.

## Highlights

- Standalone executables
- Batch input files with one row per scenario.
- Tab-delimited or comma-delimited input support.
- Composite simulations for selected categorical and numeric variables.
- Optional multi-threaded execution with `--threads auto`.
- Embedded model coefficient data for portable runs.

## Download

Download the ZIP file for your operating system from the `v1.0.0` release:

| Operating system | Processor | Download |
| --- | --- | --- |
| Windows | Intel or AMD 64-bit | [windows-x86_64.zip](https://github.com/4SAnalyticsnModelling/affirm-spatial/releases/download/v1.0.0/windows-x86_64.zip) |
| Windows | ARM64 | [windows-aarch64.zip](https://github.com/4SAnalyticsnModelling/affirm-spatial/releases/download/v1.0.0/windows-aarch64.zip) |
| macOS | Apple Silicon | [macos-aarch64.zip](https://github.com/4SAnalyticsnModelling/affirm-spatial/releases/download/v1.0.0/macos-aarch64.zip) |
| macOS | Intel | [macos-x86_64.zip](https://github.com/4SAnalyticsnModelling/affirm-spatial/releases/download/v1.0.0/macos-x86_64.zip) |
| Linux | Intel or AMD 64-bit | [linux-x86_64.zip](https://github.com/4SAnalyticsnModelling/affirm-spatial/releases/download/v1.0.0/linux-x86_64.zip) |
| Linux | ARM64 | [linux-aarch64.zip](https://github.com/4SAnalyticsnModelling/affirm-spatial/releases/download/v1.0.0/linux-aarch64.zip) |

After downloading, place the executable in your AFFIRM Spatial project folder or somewhere on your system `PATH`.

## Quick Start

This repository includes a ready-to-copy example project:

```text
examples/
  AFFIRM Spatial Project/
    input/
      AFFIRM-batch-inputs-tabs.txt
      AFFIRM-batch-inputs-commas.txt
```

Create an output folder beside the input folder:

```text
AFFIRM Spatial Project/
  input/
  output/
```

### Windows

From PowerShell:

```powershell
.\affirm_spatial.exe \
  --input "examples\AFFIRM Spatial Project\input\AFFIRM-batch-inputs-tabs.txt" \
  --output "examples\AFFIRM Spatial Project\output\AFFIRM-batch-outputs.txt" \
  --log "examples\AFFIRM Spatial Project\output\AFFIRM-batch-logfile.txt" \
  --threads auto
```

Or with comma-delimited input:

```powershell
.\affirm_spatial.exe \
  --input "examples\AFFIRM Spatial Project\input\AFFIRM-batch-inputs-commas.txt" \
  --output "examples\AFFIRM Spatial Project\output\AFFIRM-batch-outputs.txt" \
  --threads 4
```

### macOS and Linux

Make the downloaded binary executable, then run it:

```bash
chmod +x ./affirm_spatial
./affirm_spatial \
  --input "examples/AFFIRM Spatial Project/input/AFFIRM-batch-inputs-tabs.txt" \
  --output "examples/AFFIRM Spatial Project/output/AFFIRM-batch-outputs.txt" \
  --log "examples/AFFIRM Spatial Project/output/AFFIRM-batch-logfile.txt" \
  --threads auto
```

If macOS blocks the downloaded executable, remove the quarantine attribute after verifying that the file came from this repository:

```bash
xattr -d com.apple.quarantine ./affirm_spatial
```

## Command Line Reference

```text
affirm_spatial --input FILE --output FILE [--log FILE] [--threads auto|N]
```

| Option | Required | Description |
| --- | --- | --- |
| `--input FILE` | Yes | Input scenario file. Tab-delimited and comma-delimited files are supported. |
| `--output FILE` | Yes | Output results file. Existing files at this path are overwritten. |
| `--log FILE` | No | Log file path. If omitted, `AFFIRM-batch-logfile` is written beside the output file. |
| `--threads auto\|N` | No | Number of worker threads. Use `auto` to use available CPU cores. Defaults to `1`. |
| `--help` or `-h` | No | Print command usage. |

## Project File Layout

A typical AFFIRM Spatial project can use this layout:

```text
AFFIRM Spatial Project/
  input/
    AFFIRM-batch-inputs-tabs.txt
  output/
    AFFIRM-batch-outputs.txt
    AFFIRM-batch-logfile.txt
```

Do not rename columns in the input file. Change scenario values as needed, but keep the expected input column order.

## Model Inputs

The input variables are provided in the default `input/AFFIRM-batch-inputs-tabs.txt` or `input/AFFIRM-batch-inputs-commas.txt` file. Visit [AFFIRM Lite]([https://mezbahu.shinyapps.io/AFFIRM_R_version_yield_response_nitrogen/](https://www.4sanalyticsnmodelling.com/affirm-lite/)) to understand these variables better.

| Input | Value type | Notes |
| --- | --- | --- |
| `Index` | Integer | Unique ID for each scenario row in the input file. |
| `Township` | Integer | Alberta township ID, ranging from `1` to `126`. |
| `Range` | Integer | Alberta range ID, ranging from `1` to `30`. |
| `Meridian` | Category | Use `W4`, `W5`, or `W6`. |
| `Soil organic matter (0-6") (%)` | Decimal number | Soil organic matter percentage. |
| `Soil texture` | Category ID | Use one of the soil texture identifiers listed below. |
| `Spring soil moisture` | Category ID | Use one of the spring soil moisture identifiers listed below. |
| `Soil pH (0-6" or 0-12")` | Decimal number | Soil pH value. |
| `Soil EC (0-6" or 0-12") (mS/cm)` | Decimal number | Soil electrical conductivity value. |
| `Crop` | Category ID | Use one of the crop identifiers listed below. |
| `Irrigation` | Category ID | Use one of the irrigation identifiers listed below. |
| `Growing season precipitation (May-Aug) (mm)` | Decimal number or integer | Optional if unknown. Leave blank to let AFFIRM Spatial estimate this value from long-term precipitation probability distributions. |
| `Irrigation water amount, if irrigated (mm)` | Decimal number or integer | Optional if unknown. Leave blank to let AFFIRM Spatial use a typical default value. |
| `Nitrogen fertilizer product` | Category ID | Use one of the nitrogen fertilizer product identifiers listed below. |
| `Nitrogen fertilizer application timing` | Category ID | Use one of the nitrogen fertilizer application timing identifiers listed below. |
| `Nitrogen fertilizer application placement` | Category ID | Use one of the nitrogen fertilizer application placement identifiers listed below. |
| `Soil test nitrogen (0-24") (lb N/ac)` | Decimal number | Soil test nitrogen value. |
| `Previous crop` | Category ID | Use one of the previous crop identifiers listed below. |
| `Previous crop yield` | Decimal number | Previous crop yield value. |
| `Previous crop yield unit` | Category ID | Use one of the previous crop yield unit identifiers listed below. |
| `Residue management` | Category ID | Use one of the residue management identifiers listed below. |
| `Crop available nitrogen from applied manure (lb N/ac)` | Decimal number | Crop available nitrogen from applied manure. |
| `Expected crop price ($/bu)` | Decimal number | Expected crop price. |
| `Fertilizer price ($/tonne)` | Decimal number | Fertilizer price. |
| `Investment ratio` | Decimal number | User-selected investment ratio. |

## Categorical Input Identifiers

### Soil texture

| Soil texture | Identifier |
| --- | --- |
| `Very Coarse` | `1` |
| `Coarse` | `2` |
| `Medium` | `3` |
| `Fine` | `4` |
| `Very Fine` | `5` |
| `Muck` | `6` |
| `Peaty Muck` | `7` |
| `Mucky Peat` | `8` |
| `Peat` | `9` |

### Spring soil moisture

| Spring soil moisture | Identifier |
| --- | --- |
| `Low` | `1` |
| `Intermediate` | `2` |
| `Optimum` | `3` |

### Crop

| Crop | Identifier |
| --- | --- |
| `Barley (Feed and Food)` | `1` |
| `Barley (Hulless)` | `2` |
| `Barley (Malt)` | `3` |
| `Canola` | `4` |
| `Canola (Argentine)` | `5` |
| `Canola (Polish)` | `6` |
| `Flax` | `7` |
| `Oats` | `8` |
| `Triticale (Spring)` | `9` |
| `Wheat - Western Red Spring (WRS)` | `10` |
| `Wheat - Northern Hard Red (NHR)` | `11` |
| `Wheat - Western Amber Durum (WAD)` | `12` |
| `Wheat - Western Extra Strong (WES)` | `13` |
| `Wheat - Western Soft White Spring (WSWS)` | `14` |

### Irrigation

| Irrigation | Identifier |
| --- | --- |
| `No` | `1` |
| `Yes` | `2` |

### Nitrogen fertilizer product

| Nitrogen fertilizer product | Identifier |
| --- | --- |
| `ESN` | `1` |
| `ESN - Urea Blend (25:75)` | `2` |
| `ESN - Urea Blend (50:50)` | `3` |
| `ESN - Urea Blend (75:25)` | `4` |
| `SuperU` | `5` |
| `Urea` | `6` |
| `Urea + eNtrench` | `7` |
| `UAN (28-0-0) + Agrotain` | `8` |
| `UAN (28-0-0)` | `9` |
| `Anhydrous Ammonia` | `10` |
| `Ammonium Nitrate` | `11` |

### Nitrogen fertilizer application timing

| Nitrogen fertilizer application timing | Identifier |
| --- | --- |
| `Fall` | `1` |
| `Spring` | `2` |

### Nitrogen fertilizer application placement

| Nitrogen fertilizer application placement | Identifier |
| --- | --- |
| `Banded` | `1` |
| `Seed Placed` | `2` |
| `Broadcast/incorporated (Surface banded)` | `3` |
| `Broadcast` | `4` |

### Previous crop

| Previous crop | Identifier |
| --- | --- |
| `Alfalfa (Hay)` | `1` |
| `Barley (Feed and Food)` | `2` |
| `Barley (Hulless)` | `3` |
| `Barley (Malt)` | `4` |
| `Buckwheat` | `5` |
| `Canary seed` | `6` |
| `Canola` | `7` |
| `Canola (Argentine)` | `8` |
| `Canola (Hybrid)` | `9` |
| `Canola (Juncea)` | `10` |
| `Canola (Polish)` | `11` |
| `Chickpeas` | `12` |
| `Corn (Forage/Silage)` | `13` |
| `Corn (Grain)` | `14` |
| `Cowpeas` | `15` |
| `Dry Bean (Black)` | `16` |
| `Dry Bean (Great Northern)` | `17` |
| `Dry Bean (Navy)` | `18` |
| `Dry Bean (Pinto)` | `19` |
| `Dry Bean (Shiny Black)` | `20` |
| `Dry Bean (Small Red)` | `21` |
| `Dry Bean (Yellow)` | `22` |
| `Faba Bean` | `23` |
| `Field Peas (Dun)` | `24` |
| `Field Peas (Forage)` | `25` |
| `Field Peas (Green)` | `26` |
| `Field Peas (Maple)` | `27` |
| `Field Peas (Processing)` | `28` |
| `Field Peas (Red)` | `29` |
| `Field Peas (Winter)` | `30` |
| `Field Peas (Yellow)` | `31` |
| `Flax` | `32` |
| `Hay and Forage for Seed` | `33` |
| `Lentils` | `34` |
| `Lentils (Winter)` | `35` |
| `Mustard (Brown)` | `36` |
| `Mustard (Oriental)` | `37` |
| `Mustard (Yellow)` | `38` |
| `Oats (Feed)` | `39` |
| `Oats (Forage/Silage)` | `40` |
| `Oats (Hulless)` | `41` |
| `Oats (Milling)` | `42` |
| `Other Oilseed` | `43` |
| `Other Pulse (Grain)` | `44` |
| `Potatoes` | `45` |
| `Rye (Fall)` | `46` |
| `Rye (Spring)` | `47` |
| `Safflower` | `48` |
| `Soybeans` | `49` |
| `Sugar beets` | `50` |
| `Sunflowers` | `51` |
| `Tame Hay (Legumes and Mix)` | `52` |
| `Tame Hay (Other)` | `53` |
| `Triticale (Spring)` | `54` |
| `Triticale (Winter)` | `55` |
| `Wheat - Northern Hard Red (NHR)` | `56` |
| `Wheat - Prairie Spring Red (PSR)` | `57` |
| `Wheat - Prairie Spring White (PSW)` | `58` |
| `Wheat - Western Amber Durum (WAD)` | `59` |
| `Wheat - Western Extra Strong (WES)` | `60` |
| `Wheat - Western Hard White Spring (WHWS)` | `61` |
| `Wheat - Western Red Spring (WRS)` | `62` |
| `Wheat - Western Red Winter (WRW)` | `63` |
| `Wheat - Western Soft White Spring (WSWS)` | `64` |
| `Wheat - Western Special Purpose (WSP)` | `65` |

### Previous crop yield unit

| Previous crop yield unit | Identifier and usage |
| --- | --- |
| `tons/ac` | `1` (must be used with previous crop IDs `1`, `13`, `45`, `50`, `52`, and `53`) |
| `bu/ac` | `2` (must be used with all previous crop IDs except for the ones with above and below units) |
| `lb/ac` | `3` (must be used with previous crop IDs `6`, `33`, and `51`) |

### Residue management

| Residue management | Identifier |
| --- | --- |
| `Soil Incorporated` | `1` |
| `Removed from Field` | `2` |
| `Removed by Burning` | `3` |

## Composite Simulations

### Categorical variables

Composite simulations are allowed for the following categorical variables:

```text
- Soil texture
- Spring soil moisture
- Nitrogen fertilizer application timing
- Nitrogen fertilizer application placement
- Residue management
```

Use pipe-separated identifiers in a single cell. For example, to run both `Fall` and `Spring` scenarios for `Nitrogen fertilizer application timing`, enter:

```text
1|2
```

### Numerical variables

Composite simulations are allowed for the following numerical variables:

```text
- Soil organic matter (0-6") (%)
- Soil pH (0-6" or 0-12")
- Soil EC (0-6" or 0-12") (mS/cm)
- Growing season precipitation (May-Aug) (mm)
- Irrigation water amount, if irrigated (mm)
- Soil test nitrogen (0-24") (lb N/ac)
- Previous crop yield
- Crop available nitrogen from applied manure (lb N/ac)
- Expected crop price ($/bu)
- Fertilizer price ($/tonne)
- Investment ratio
```

#### 1. Step-wise simulations

Use four pipe-separated values:

```text
[lower limit]|[upper limit]|1|[interval]
```

Example: fertilizer price from `$650` to `$700` per tonne at `$10` intervals:

```text
650|700|1|10
```

#### 2. Monte Carlo simulations with random uniform sampling

Use four pipe-separated values:

```text
[lower limit]|[upper limit]|2|[number of iterations]
```

Example: fertilizer price from `$650` to `$700` per tonne, sampled 10 times:

```text
650|700|2|10
```

#### 3. Monte Carlo simulations with random normal sampling

Use four pipe-separated values:

```text
[average]|[standard deviation]|3|[number of iterations]
```

Example: fertilizer price with average `$675` per tonne, standard deviation `$20`, sampled 10 times:

```text
675|20|3|10
```

## Outputs

Results are written to the path provided with `--output`. The file is tab-delimited and includes one or more rows per input scenario, depending on the composite simulations requested.

Important messages are written to the log file. If the run completes successfully, the log ends with:

```text
Success: AFFIRM Spatial model run has completed successfully.
```

Output variables:

| Output variable | Description |
| --- | --- |
| `Index` |  |
| `Township` |  |
| `Range` |  |
| `Meridian` |  |
| `Soil Zone` | Name of the agricultural soil zone of Alberta which the township falls under. |
| `Soil organic matter (0-6") (%)` |  |
| `Soil texture` |  |
| `Spring soil moisture` |  |
| `Soil pH (0-6" or 0-12")` |  |
| `Soil EC (0-6" or 0-12") (mS/cm)` |  |
| `Crop` |  |
| `Irrigation` |  |
| `Growing season moisture flag` | Indicates whether moisture is a user input or a long-term precipitation probability estimate representing low, intermediate, or optimum moisture conditions. |
| `Growing season precipitation (May-Aug) + irrigation (if any) (mm)` | Indicates whether precipitation plus irrigation is a user input or a typical estimate representing low, intermediate, or optimum irrigation levels. |
| `Nitrogen fertilizer product` |  |
| `Nitrogen fertilizer application timing` |  |
| `Nitrogen fertilizer application placement` |  |
| `Soil test nitrogen (0-24") (lb N/ac)` |  |
| `Previous crop` |  |
| `Previous crop yield` |  |
| `Previous crop yield unit` |  |
| `Residue management` |  |
| `Crop available nitrogen from applied manure (lb N/ac)` |  |
| `Expected crop price ($/bu)` |  |
| `Fertilizer price ($/tonne)` |  |
| `User chosen investment ratio` |  |
| `Estimated N release from N mineralization over the growing season (lb N/ac)` |  |
| `N credit from previous crop residue (lb N/ac)` |  |
| `Total plant available nitrogen from soil (lb N/ac)` | Sum of estimated N release from mineralization over the growing season, N credit from previous crop residue, soil test nitrogen, and crop available nitrogen from applied manure. |
| `Fertilizer N application rate (lb N/ac)` |  |
| `Predicted crop yield (bu/ac)` |  |
| `Predicted yield increase (bu/ac)` |  |
| `Added yield increase (bu/ac)` |  |
| `Estimated revenue from fertilizer N ($/ac)` |  |
| `Marginal return or Gross margin change ($/ac)` |  |
| `Total cost of fertilizer N ($/ac)` |  |
| `Marginal cost of fertilizer N ($/ac)` |  |
| `Estimated Investment Ratio` |  |
| `Recommended?` | A `Yes` flag indicates that the nitrogen rate and predicted crop yield in that row are economically optimum for the given scenario. |
| `Comment` |  |

## Build From Source

AFFIRM Spatial is implemented in `Zig 0.16.0`. To build locally:

```bash
zig build
```

Run tests:

```bash
zig build test
```

Build release binaries for supported targets:

```bash
zig build dist
```

Generated release binaries are placed under `zig-out/dist/`. 
