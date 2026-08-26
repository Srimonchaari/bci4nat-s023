# 🧠 BCI4NAT Seminar Report

A BCI4NAT (Brain-Computer Interfaces for Neurotechnology) seminar project for BTU Cottbus-Senftenberg, Summer Semester 2026. This repo contains the full analysis pipeline and report for classifying imagined hand vs. foot movement from EEG, subject S023.

## 📋 What was assigned

The course task ([Guide /1_BCI4NAT_SS26_seminar_report instructions.pdf](Guide%20/1_BCI4NAT_SS26_seminar_report%20instructions.pdf)) asks for three things:

- 🔍 **Dataset exploration**: understand the mental state being studied, the experimental paradigm, the recording equipment, and the dataset structure before touching the data.
- 🧪 **EEG analysis in EEGLAB**: re-reference, filter, run ICA, epoch the data, justify two removed and two kept ICA components, and visualize the two conditions (hand vs. foot) side by side.
- 🤖 **BCI classification in BCILAB**: extract features, train a classifier, cross-validate, report chance level, and visualize what the trained model is actually relying on.

Code and data processing must use **EEGLAB and BCILAB functions only**, no other MATLAB toolboxes. The report follows a fixed template (Introduction, Methods, Results, Discussion, References), capped at **15 pages**, cited in **APA style**.

## 👥 Pair and dataset

- **Srimonchaari Padmanabhan Babu**, Matrikelnummer 5012061
- **Andrew David Flavian Kanickairaj**, Matrikelnummer 5008579

The course pairs each pair with one dataset via a poll, exclusive per pair. Our confirmed selection is **S023_hand_vs_foot**.

The underlying data is the **PhysioNet EEG Motor Movement/Imagery Dataset** (Schalk, McFarland, Hinterberger, Birbaumer & Wolpaw, 2004), also mirrored on [NEMAR](https://nemar.org/dataset/on004362). Key facts:

- 64-channel EEG (international 10-10 system), BCI2000 acquisition system, 160 Hz sampling rate.
- Subject S023, Task 4: imagined hand (both fists) vs. imagined foot movement.
- Event markers: `T0` = rest, `T1` = hand imagery, `T2` = foot imagery.
- 45 usable trials after preprocessing: 23 hand, 22 foot.

## 🛠️ What we built

### Preprocessing (EEGLAB)

`Code/eeglab_preprocess_S023.m` takes the raw dataset and:

- Re-references to the average of all 64 channels.
- Band-pass filters 7 to 30 Hz (zero-phase FIR), plus a 50 Hz notch filter.
- Resamples to 100 Hz.
- Runs ICA (extended infomax) on the continuous, filtered data.
- Removes two artifact components (IC6, IC15, muscle-like, justified by topography, spectrum, and time-course), keeps two brain-like components (IC1, IC4, posterior alpha and sensorimotor, same three-axis justification).
- Epochs from −0.5 s to 3.5 s around each cue and baseline-corrects.
- Saves both a cleaned continuous dataset (for submission) and a cleaned epoched dataset (for analysis).

### Classification (BCILAB)

`Code/bcilab_pipeline_S023.m` runs the actual graded classification pipeline:

- CSP (Common Spatial Patterns) feature extraction, 3 pattern pairs, via BCILAB's `ParadigmCSP`.
- LDA (Linear Discriminant Analysis) classifier via `ml_trainlda`.
- 5-fold cross-validation via `bci_train`.
- Computes a pooled confusion matrix from the actual per-trial predictions.
- Generates the CSP spatial-pattern figure directly from the trained BCILAB model.

### Comparison figures (EEGLAB)

`Code/eeg_comparison_figures_S023.m` computes event-related desynchronisation (ERD%) for hand vs. foot imagery and produces the spectral and topographic comparison figures used in the Results section.

### Manual cross-check (MATLAB, not part of the graded submission)

`Code/csp_lda_cv_S023.m` is a second, independent CSP+LDA implementation written directly in MATLAB (not through BCILAB). It exists only as a sanity check on the BCILAB result and is explicitly marked as **not** satisfying the "EEGLAB/BCILAB only" rule, so it is not part of the Part C code submission.

## 📊 What we found

- **Classification accuracy: 73.33%** (BCILAB CSP+LDA, 5-fold cross-validation) against a theoretical chance level of **51.11%**, clearly above chance.
- The classifier is noticeably better at recognizing **foot** imagery (81.8% correct) than **hand** imagery (65.2% correct).
- **ERD is real and spatially structured**: foot imagery shows a deeper mu-band dip at the midline electrode (Cz) than hand imagery does, matching the expected somatotopic layout of motor cortex (leg/foot area medial, hand area lateral).
- A manual, non-BCILAB CSP+LDA cross-check on the same cleaned data reached a higher accuracy (~87%), traced to a genuine difference in how the two implementations estimate class covariance matrices, not a bug. Both numbers are reported; the BCILAB result is the one submitted, since the assignment requires BCILAB specifically.
- The absolute ERD% values run higher than typical published figures, traced to a short 0.5 s pre-cue baseline window. Disclosed as a known limitation rather than hidden.

## 📁 Project layout

- `Guide /`: the three PDFs defining the assignment (task instructions, grading rubric, BTU academic writing guide).
- `Dataset/`: raw and cleaned EEG data for subject S023.
- `Code/`: MATLAB scripts (EEGLAB + BCILAB only, per assignment rules).
- `Results&Figures/`: figures and result files generated by the pipeline.
- `Report/`: reference material, kept untouched.
- `Report_New/`: the working report. LaTeX source (`report_template.tex`), bibliography (`references.bib`), and compiled output (`report_template.pdf`). This is the submittable report.

## ✅ Status

Report content is complete: Introduction, Methods, Results (with confusion matrix), and Discussion are all written, cited, and figure-complete. Compiles cleanly to 12 pages, well under the 15-page limit. See [TODO.md](TODO.md) for the current task list and [CLAUDE.md](CLAUDE.md) for the working rules this project follows.
