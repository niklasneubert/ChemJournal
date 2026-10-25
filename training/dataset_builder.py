#!/usr/bin/env python3
"""
dataset_builder.py – Trainingsdaten für ChemJournal „Smart Extract“ (Create ML Word Tagger)

Was sich gegenüber der alten Version geändert hat
-------------------------------------------------
1. Tokenisierung wie in der App. Die alte Version hat Tokens in Python von Hand zusammengesetzt
   ("3.50 g", "Pd(PPh3)4", "n-BuLi" als je ein Token). In der App zerlegt NLTagger den Text aber selbst
   ("3.50" "g", "Pd" "(" "PPh3" ")" "4", "n" "-" "BuLi") und gibt dem Modell auch die Satzzeichen.
   Jetzt erzeugt der Generator Text + Zeichenbereiche je Label; `nl_tokenizer.swift` normalisiert den
   Text mit derselben Swift-Funktion wie die App und tokenisiert ihn mit NLTagger. Labels werden über
   die Zeichenbereiche vergeben – verschobene Labels sind damit ausgeschlossen.
2. Vielfalt. Statt ~11 starrer Satzschablonen gibt es 27 Satzbausteine (DE/EN) mit wechselnden Mengen-
   Reihenfolgen, Klammer- und klammerlosen Schreibweisen, Lösungen ("2.5 M in hexanes"), mol%,
   Hydraten (CuSO4·5H2O), Salzen, metallorganischen Reagenzien, Verbindungsnummern, Stereodeskriptoren,
   Temperatur-, Zeit- und Kolben-Distraktoren sowie Aufarbeitung und Produktangaben. Jedes Beispiel ist
   ein Absatz aus 1–3 Sätzen.
3. Realistische Zahlen. Molmassen und Dichten kommen aus `chem_ontology.py` bzw. den Listen unten;
   Masse, Stoffmenge, Volumen und Äquivalente passen zueinander (vorher pauschal 120 g/mol).
4. Testdaten mit ungesehenen Namen. 15 % der Chemikaliennamen kommen nur im Testsplit vor, damit die
   Testgenauigkeit nicht bloß Auswendiglernen misst (vorher 99.9 % auf test.json, 81.6 % im Benchmark).
5. Kompatibilität mit den goldenen Benchmarks. Ein Teil der Beispiele (`legacy_share`) wird im alten
   Token-Stil ausgegeben ("3.50 g" als ein Token), weil `testdaten_1.json`/`testdaten_NEU.json`
   so tokenisiert sind und nicht verändert werden dürfen.

Label-Policy (6 Create-ML-Klassen)
----------------------------------
CHEMICAL  Name, Formel, Abkürzung oder Verbindungsnummer eines Edukts, Reagenzes, Katalysators,
          Liganden oder Reaktionslösemittels – inkl. Bindestriche/Klammern im Namen und Präfixen wie
          "10% Pd/C". Auch ein Kurzname in Klammern ("ethyl acetate (EtOAc, 2 mL)").
MASS      Zahl + Masseneinheit (µg, mg, g, kg).
AMOUNT    Zahl + Stoffmengeneinheit (µmol, mmol, mol).
VOLUME    Zahl + Volumeneinheit (µL, mL, L) eines Reagenzes oder Lösemittels.
EQ        Äquivalente (eq, equiv., Äq., Äquiv.) und Katalysatorbeladung (mol%, mol-%).
NONE      Alles andere, insbesondere Temperaturen, Zeiten, Konzentrationen ("2.5 M"), das Trägerlösemittel
          einer Reagenzlösung ("in hexanes", "als THF-Lösung"), Kolben-/Gefäßvolumina, Druck,
          Verhältnisse ("4:1"), Ausbeuten und sämtliche Aufarbeitungs-, Reinigungs- und Produktsätze
          (Extrahieren, Waschen, Trocknen, Quenchen, Chromatographie, "afforded …"). Diese Sätze
          überspringt die App ohnehin (SmartExtractor.isWorkupOrProduct).

Hinweis: `testdaten_NEU.json` labelt "Die organische Phase wurde mit X mL Y gewaschen" und
"diluted with … and washed with …" als VOLUME/CHEMICAL, "Gewaschen wurde mit …" und "extracted with …"
dagegen als NONE. Diese Policy folgt durchgängig der zweiten Variante.
"""

from __future__ import annotations

import hashlib
import json
import math
import random
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from chem_ontology import CHEMICAL_DATABASE

ROOT = Path(__file__).resolve().parent
LABELS = ("CHEMICAL", "MASS", "AMOUNT", "VOLUME", "EQ", "NONE")
# Muss zur Sprache des Create-ML-Modells passen (Projekt-Einstellung "wtLanguage": "en").
# SmartExtractor setzt dieselbe Sprache am NLTagger.
MODEL_LANGUAGE = "en"

# ============================================================================
# Chemikalien
# ============================================================================


@dataclass(frozen=True)
class Chem:
    de: tuple[str, ...]
    en: tuple[str, ...]
    M: float
    d: float | None = None
    role: str = "reagent"                 # reactant, reagent, catalyst, ligand, solvent, salt
    liquid: bool = False
    solution: tuple[float, str, str] | None = None   # (Molarität, Lösemittel DE, Lösemittel EN)

    def name(self, rng: random.Random, lang: str) -> str:
        return rng.choice(self.de if lang == "de" else self.en)

    @property
    def key(self) -> str:
        return self.en[0]


_SOLID_HINTS = ("acid", "hydride", "carbonate", "hydroxide", "boronic", "succinimide", "periodinane", "IBX",
                "phosphine", "sodium", "potassium", "cesium", "salicylic", "vanillin", "menthol", "camphor",
                "maleic", "mCPBA", "HATU", "HOBt", "EDCI", "DCC", "iodide", "sulfate", "ascorbate", "BINAP",
                "Phos", "palladium", "Grubbs")


def _from_ontology() -> list[Chem]:
    out = []
    for e in CHEMICAL_DATABASE:
        abbr = e.get("abbr")
        de = (e["name_de"],) + ((abbr,) if abbr else ())
        en = (e["name_en"],) + ((abbr,) if abbr else ())
        d = e.get("d")
        liquid = e["role"] == "solvent" or (
            d is not None and d < 1.9 and e["role"] != "catalyst" and not any(h in e["name_en"] for h in _SOLID_HINTS))
        out.append(Chem(de, en, e["M"], d, e["role"], liquid))
    return out


# Reagenzien, die als Lösung gehandelt werden
ORGANOMETALLICS = [
    Chem(("n-Butyllithium", "n-BuLi"), ("n-butyllithium", "n-BuLi"), 64.06, None, "reagent", True, (2.5, "Hexan", "hexanes")),
    Chem(("n-Butyllithium", "n-BuLi"), ("n-BuLi",), 64.06, None, "reagent", True, (1.6, "Hexan", "hexanes")),
    Chem(("sec-Butyllithium", "s-BuLi"), ("sec-butyllithium", "s-BuLi"), 64.06, None, "reagent", True, (1.4, "Cyclohexan", "cyclohexane")),
    Chem(("tert-Butyllithium", "t-BuLi"), ("tert-butyllithium", "t-BuLi"), 64.06, None, "reagent", True, (1.7, "Pentan", "pentane")),
    Chem(("Methyllithium", "MeLi"), ("methyllithium", "MeLi"), 21.98, None, "reagent", True, (1.6, "Et2O", "Et2O")),
    Chem(("Phenyllithium", "PhLi"), ("phenyllithium", "PhLi"), 84.04, None, "reagent", True, (1.9, "Dibutylether", "dibutyl ether")),
    Chem(("Methylmagnesiumbromid", "MeMgBr"), ("methylmagnesium bromide", "MeMgBr"), 119.24, None, "reagent", True, (3.0, "Et2O", "Et2O")),
    Chem(("Ethylmagnesiumbromid", "EtMgBr"), ("ethylmagnesium bromide", "EtMgBr"), 133.27, None, "reagent", True, (3.0, "Et2O", "Et2O")),
    Chem(("Isopropylmagnesiumchlorid-Lithiumchlorid", "iPrMgCl·LiCl"), ("iPrMgCl·LiCl",), 145.24, None, "reagent", True, (1.3, "THF", "THF")),
    Chem(("Phenylmagnesiumbromid", "PhMgBr"), ("phenylmagnesium bromide", "PhMgBr"), 181.31, None, "reagent", True, (1.0, "THF", "THF")),
    Chem(("Vinylmagnesiumbromid",), ("vinylmagnesium bromide",), 131.26, None, "reagent", True, (1.0, "THF", "THF")),
    Chem(("Allylmagnesiumbromid",), ("allylmagnesium bromide", "allylMgBr"), 145.28, None, "reagent", True, (1.0, "Et2O", "Et2O")),
    Chem(("Diisobutylaluminiumhydrid", "DIBAL-H"), ("diisobutylaluminum hydride", "DIBAL-H"), 142.22, None, "reagent", True, (1.0, "Toluol", "toluene")),
    Chem(("Lithiumhexamethyldisilazid", "LiHMDS"), ("lithium bis(trimethylsilyl)amide", "LiHMDS"), 167.33, None, "reagent", True, (1.0, "THF", "THF")),
    Chem(("Natriumhexamethyldisilazid", "NaHMDS"), ("sodium bis(trimethylsilyl)amide", "NaHMDS"), 183.38, None, "reagent", True, (2.0, "THF", "THF")),
    Chem(("Kaliumhexamethyldisilazid", "KHMDS"), ("KHMDS",), 199.48, None, "reagent", True, (0.5, "Toluol", "toluene")),
    Chem(("Lithiumdiisopropylamid", "LDA"), ("lithium diisopropylamide", "LDA"), 107.12, None, "reagent", True, (2.0, "THF", "THF")),
    Chem(("Diethylzink", "Et2Zn"), ("diethylzinc", "Et2Zn"), 123.50, None, "reagent", True, (1.0, "Hexan", "hexanes")),
    Chem(("Boran-THF-Komplex", "BH3·THF"), ("borane tetrahydrofuran complex", "BH3·THF"), 85.94, None, "reagent", True, (1.0, "THF", "THF")),
    Chem(("Lithiumaluminiumhydrid", "LiAlH4"), ("lithium aluminum hydride", "LiAlH4"), 37.95, None, "reagent", True, (2.4, "THF", "THF")),
    Chem(("Tetrabutylammoniumfluorid", "TBAF"), ("tetrabutylammonium fluoride", "TBAF"), 261.47, None, "reagent", True, (1.0, "THF", "THF")),
    Chem(("Trimethylaluminium", "AlMe3"), ("trimethylaluminum", "AlMe3"), 72.09, None, "reagent", True, (2.0, "Toluol", "toluene")),
    Chem(("HCl",), ("HCl",), 36.46, None, "reagent", True, (4.0, "Dioxan", "dioxane")),
]

HYDRATES = [
    Chem(("CuSO4·5H2O", "Kupfer(II)-sulfat-Pentahydrat"), ("CuSO4·5H2O", "copper(II) sulfate pentahydrate"), 249.68, None, "catalyst"),
    Chem(("NiCl2·6H2O", "Nickel(II)-chlorid-Hexahydrat"), ("NiCl2·6H2O", "nickel(II) chloride hexahydrate"), 237.69, None, "catalyst"),
    Chem(("CeCl3·7H2O", "Cer(III)-chlorid-Heptahydrat"), ("CeCl3·7H2O", "cerium(III) chloride heptahydrate"), 372.58, None, "reagent"),
    Chem(("FeCl3·6H2O", "Eisen(III)-chlorid-Hexahydrat"), ("FeCl3·6H2O",), 270.30, None, "catalyst"),
    Chem(("CoCl2·6H2O",), ("CoCl2·6H2O", "cobalt(II) chloride hexahydrate"), 237.93, None, "catalyst"),
    Chem(("SnCl2·2H2O", "Zinn(II)-chlorid-Dihydrat"), ("SnCl2·2H2O", "tin(II) chloride dihydrate"), 225.65, None, "reagent"),
    Chem(("p-TsOH·H2O", "p-Toluolsulfonsäure-Monohydrat"), ("p-TsOH·H2O", "p-toluenesulfonic acid monohydrate"), 190.22, None, "catalyst"),
    Chem(("LiOH·H2O", "Lithiumhydroxid-Monohydrat"), ("LiOH·H2O", "lithium hydroxide monohydrate"), 41.96, None, "reagent"),
    Chem(("Ba(OH)2·8H2O",), ("Ba(OH)2·8H2O",), 315.46, None, "reagent"),
    Chem(("Na2S·9H2O", "Natriumsulfid-Nonahydrat"), ("Na2S·9H2O",), 240.18, None, "reagent"),
    Chem(("Pd(dppf)Cl2·CH2Cl2",), ("Pd(dppf)Cl2·CH2Cl2",), 816.64, None, "catalyst"),
    Chem(("CuBr·SMe2",), ("CuBr·SMe2",), 205.57, None, "catalyst"),
    Chem(("Ru(bpy)3Cl2·6H2O",), ("Ru(bpy)3Cl2·6H2O",), 748.63, None, "catalyst"),
]

SALTS = [
    Chem(("Ammoniumchlorid", "NH4Cl"), ("ammonium chloride", "NH4Cl"), 53.49, None, "salt"),
    Chem(("Natriumchlorid", "NaCl"), ("sodium chloride", "NaCl"), 58.44, None, "salt"),
    Chem(("Kaliumiodid", "KI"), ("potassium iodide", "KI"), 166.00, None, "salt"),
    Chem(("Natriumiodid", "NaI"), ("sodium iodide", "NaI"), 149.89, None, "salt"),
    Chem(("Lithiumchlorid", "LiCl"), ("lithium chloride", "LiCl"), 42.39, None, "salt"),
    Chem(("Cäsiumfluorid", "CsF"), ("cesium fluoride", "CsF"), 151.90, None, "salt"),
    Chem(("Kaliumfluorid", "KF"), ("potassium fluoride", "KF"), 58.10, None, "salt"),
    Chem(("Natriumazid", "NaN3"), ("sodium azide", "NaN3"), 65.01, None, "reagent"),
    Chem(("Kalium-tert-butanolat", "KOtBu"), ("potassium tert-butoxide", "KOtBu", "tBuOK"), 112.21, None, "reagent"),
    Chem(("Natriummethanolat", "NaOMe"), ("sodium methoxide", "NaOMe"), 54.02, None, "reagent"),
    Chem(("Kaliumphosphat", "K3PO4"), ("potassium phosphate", "K3PO4"), 212.27, None, "reagent"),
    Chem(("Kaliumacetat", "KOAc"), ("potassium acetate", "KOAc"), 98.14, None, "reagent"),
    Chem(("Natriumacetat", "NaOAc"), ("sodium acetate", "NaOAc"), 82.03, None, "reagent"),
    Chem(("Natriumcarbonat", "Na2CO3"), ("sodium carbonate", "Na2CO3"), 105.99, None, "reagent"),
    Chem(("Natriumhydrogencarbonat", "NaHCO3"), ("sodium bicarbonate", "NaHCO3"), 84.01, None, "reagent"),
    Chem(("Silbercarbonat", "Ag2CO3"), ("silver carbonate", "Ag2CO3"), 275.75, None, "reagent"),
    Chem(("Silbertriflat", "AgOTf"), ("silver triflate", "AgOTf"), 256.94, None, "reagent"),
    Chem(("Zinktriflat", "Zn(OTf)2"), ("zinc triflate", "Zn(OTf)2"), 363.53, None, "catalyst"),
    Chem(("Scandiumtriflat", "Sc(OTf)3"), ("scandium triflate", "Sc(OTf)3"), 492.16, None, "catalyst"),
    Chem(("Kupfer(II)-triflat", "Cu(OTf)2"), ("copper(II) triflate", "Cu(OTf)2"), 361.68, None, "catalyst"),
    Chem(("Tetrabutylammoniumiodid", "TBAI"), ("tetrabutylammonium iodide", "TBAI"), 369.37, None, "catalyst"),
    Chem(("Natriumcyanoborhydrid", "NaBH3CN"), ("sodium cyanoborohydride", "NaBH3CN"), 62.84, None, "reagent"),
    Chem(("Natriumtriacetoxyborhydrid", "NaBH(OAc)3"), ("sodium triacetoxyborohydride", "NaBH(OAc)3"), 211.94, None, "reagent"),
    Chem(("Natriumascorbat",), ("sodium ascorbate",), 198.11, None, "reagent"),
    Chem(("Selectfluor",), ("Selectfluor",), 354.26, None, "reagent"),
    Chem(("Oxone",), ("Oxone",), 614.76, None, "reagent"),
    Chem(("Kaliumselenocyanat", "KSeCN"), ("potassium selenocyanate", "KSeCN"), 144.08, None, "reagent"),
]

CATALYSTS = [
    Chem(("[Ir(dF(CF3)ppy)2(dtbbpy)]PF6",), ("[Ir(dF(CF3)ppy)2(dtbbpy)]PF6",), 1122.2, None, "catalyst"),
    Chem(("4CzIPN",), ("4CzIPN",), 788.9, None, "catalyst"),
    Chem(("5CzBN",), ("5CzBN",), 789.9, None, "catalyst"),
    Chem(("Eosin Y",), ("eosin Y",), 691.9, None, "catalyst"),
    Chem(("Pd(PPh3)2Cl2",), ("Pd(PPh3)2Cl2", "bis(triphenylphosphine)palladium(II) dichloride"), 701.9, None, "catalyst"),
    Chem(("Ni(cod)2",), ("Ni(cod)2",), 275.1, None, "catalyst"),
    Chem(("NiCl2·glyme",), ("NiCl2·glyme",), 219.7, None, "catalyst"),
    Chem(("Rh2(OAc)4",), ("Rh2(OAc)4",), 441.99, None, "catalyst"),
    Chem(("Grubbs-II-Katalysator",), ("Grubbs II", "Grubbs second-generation catalyst"), 848.97, None, "catalyst"),
    Chem(("Hoveyda-Grubbs-II-Katalysator",), ("Hoveyda-Grubbs II",), 626.6, None, "catalyst"),
    Chem(("Fe(acac)3",), ("Fe(acac)3",), 353.17, None, "catalyst"),
    Chem(("Cu(OAc)2",), ("Cu(OAc)2",), 181.63, None, "catalyst"),
    Chem(("Pd(TFA)2",), ("Pd(TFA)2",), 332.45, None, "catalyst"),
    Chem(("AuCl(PPh3)",), ("AuCl(PPh3)",), 494.7, None, "catalyst"),
    Chem(("PtO2",), ("PtO2", "Adams' catalyst"), 227.08, None, "catalyst"),
    Chem(("10% Pd/C", "Pd/C"), ("10% Pd/C", "Pd/C"), 106.42, None, "catalyst"),
]

LIGANDS = [
    Chem(("dppf",), ("dppf",), 554.4, None, "ligand"),
    Chem(("Xantphos",), ("Xantphos",), 578.6, None, "ligand"),
    Chem(("RuPhos",), ("RuPhos",), 466.6, None, "ligand"),
    Chem(("BrettPhos",), ("BrettPhos",), 536.7, None, "ligand"),
    Chem(("XPhos",), ("XPhos",), 476.7, None, "ligand"),
    Chem(("SPhos",), ("SPhos",), 410.5, None, "ligand"),
    Chem(("dtbbpy",), ("dtbbpy", "4,4'-di-tert-butyl-2,2'-bipyridine"), 268.4, None, "ligand"),
    Chem(("1,10-Phenanthrolin",), ("1,10-phenanthroline",), 180.2, None, "ligand"),
    Chem(("(S)-BINAP",), ("(S)-BINAP", "(R)-BINAP"), 622.7, None, "ligand"),
    Chem(("(S)-BINOL", "(R)-BINOL"), ("(S)-BINOL", "(R)-BINOL", "(±)-BINOL"), 286.3, None, "ligand"),
    Chem(("TMEDA",), ("TMEDA",), 116.2, 0.775, "ligand", True),
]

EXTRA_LIQUIDS = [
    Chem(("Diisopropylamin",), ("diisopropylamine", "iPr2NH"), 101.19, 0.717, "reagent", True),
    Chem(("DMPU",), ("DMPU",), 128.17, 1.06, "reagent", True),
    Chem(("HMPA",), ("HMPA",), 179.20, 1.03, "reagent", True),
    Chem(("Triethylsilan", "Et3SiH"), ("triethylsilane", "Et3SiH"), 116.28, 0.728, "reagent", True),
    Chem(("Trimethylsilylcyanid", "TMSCN"), ("trimethylsilyl cyanide", "TMSCN"), 99.21, 0.744, "reagent", True),
    Chem(("Trifluormethansulfonsäureanhydrid", "Tf2O"), ("triflic anhydride", "Tf2O"), 282.14, 1.677, "reagent", True),
    Chem(("Methansulfonylchlorid", "MsCl"), ("methanesulfonyl chloride", "MsCl"), 114.55, 1.48, "reagent", True),
    Chem(("Acetylchlorid", "AcCl"), ("acetyl chloride", "AcCl"), 78.50, 1.104, "reagent", True),
    Chem(("Benzoylchlorid", "BzCl"), ("benzoyl chloride", "BzCl"), 140.57, 1.21, "reagent", True),
    Chem(("Allylbromid",), ("allyl bromide",), 120.98, 1.398, "reagent", True),
    Chem(("Propargylbromid",), ("propargyl bromide",), 118.96, 1.57, "reagent", True),
    Chem(("2,6-Lutidin",), ("2,6-lutidine",), 107.15, 0.92, "reagent", True),
    Chem(("DBU",), ("DBU",), 152.24, 1.018, "reagent", True),
    Chem(("Essigsäure", "AcOH"), ("acetic acid", "AcOH"), 60.05, 1.049, "reagent", True),
    Chem(("Hydrazinhydrat", "N2H4·H2O"), ("hydrazine hydrate", "N2H4·H2O"), 50.06, 1.032, "reagent", True),
    Chem(("Wasserstoffperoxid",), ("hydrogen peroxide",), 34.01, 1.11, "reagent", True),
]

EXTRA_SOLVENTS = [
    Chem(("CH2Cl2",), ("CH2Cl2",), 84.93, 1.326, "solvent", True),
    Chem(("Chloroform", "CHCl3"), ("chloroform", "CHCl3"), 119.38, 1.49, "solvent", True),
    Chem(("1,2-Dichlorethan", "DCE"), ("1,2-dichloroethane", "DCE", "1,2-DCE"), 98.96, 1.253, "solvent", True),
    Chem(("HFIP",), ("HFIP",), 168.04, 1.596, "solvent", True),
    Chem(("TFE",), ("TFE", "2,2,2-trifluoroethanol"), 100.04, 1.383, "solvent", True),
    Chem(("NMP",), ("NMP",), 99.13, 1.028, "solvent", True),
    Chem(("DMA",), ("DMA", "N,N-dimethylacetamide"), 87.12, 0.937, "solvent", True),
    Chem(("2-MeTHF",), ("2-MeTHF",), 86.13, 0.854, "solvent", True),
    Chem(("CPME",), ("CPME",), 100.16, 0.86, "solvent", True),
    Chem(("MTBE",), ("MTBE",), 88.15, 0.74, "solvent", True),
    Chem(("tBuOH",), ("tBuOH", "tert-butanol"), 74.12, 0.775, "solvent", True),
    Chem(("Cyclohexan",), ("cyclohexane",), 84.16, 0.779, "solvent", True),
    Chem(("Benzol",), ("benzene",), 78.11, 0.877, "solvent", True),
    Chem(("Chlorbenzol", "PhCl"), ("chlorobenzene", "PhCl"), 112.56, 1.11, "solvent", True),
    Chem(("Xylol",), ("xylene", "o-xylene"), 106.17, 0.88, "solvent", True),
    Chem(("Aceton",), ("acetone",), 58.08, 0.784, "solvent", True),
    Chem(("CH3CN",), ("CH3CN",), 41.05, 0.786, "solvent", True),
]

_ONTOLOGY = _from_ontology()
SOLVENTS = [c for c in _ONTOLOGY if c.role == "solvent"] + EXTRA_SOLVENTS
REACTANTS = [c for c in _ONTOLOGY if c.role == "reactant"]
REAGENTS = [c for c in _ONTOLOGY if c.role == "reagent"] + EXTRA_LIQUIDS + SALTS
LIQUID_REAGENTS = [c for c in REAGENTS if c.liquid]
SOLID_REAGENTS = [c for c in REAGENTS if not c.liquid]
CATS = [c for c in _ONTOLOGY if c.role == "catalyst"] + CATALYSTS + [h for h in HYDRATES if h.role == "catalyst"]

# Bausteine für systematische Namen ("4-Brom-2-fluorbenzaldehyd", "methyl 4-bromobenzoate")
_SUBST = [("Brom", "bromo"), ("Chlor", "chloro"), ("Fluor", "fluoro"), ("Iod", "iodo"), ("Methoxy", "methoxy"),
          ("Methyl", "methyl"), ("Nitro", "nitro"), ("Trifluormethyl", "(trifluoromethyl)"), ("Cyano", "cyano"),
          ("Hydroxy", "hydroxy"), ("Amino", "amino"), ("Ethoxy", "ethoxy"), ("Phenyl", "phenyl"), ("Benzyloxy", "benzyloxy")]
_PARENT = [("benzaldehyd", "benzaldehyde", 106), ("anilin", "aniline", 93), ("pyridin", "pyridine", 79),
           ("phenol", "phenol", 94), ("acetophenon", "acetophenone", 120), ("benzylalkohol", "benzyl alcohol", 108),
           ("brombenzol", "bromobenzene", 157), ("benzoesäuremethylester", "methyl benzoate", 136),
           ("benzonitril", "benzonitrile", 103), ("styrol", "styrene", 104), ("indol", "indole", 117),
           ("phenylboronsäure", "phenylboronic acid", 122), ("benzoesäure", "benzoic acid", 122),
           ("thiophen", "thiophene", 84), ("chinolin", "quinoline", 129), ("piperidin", "piperidine", 85)]
_STEREO = ["(S)-", "(R)-", "(±)-", "rac-", "(1R,2S)-", "(E)-", "(Z)-"]
_CHIRAL = [("1-Phenylethanol", "1-phenylethanol", 122), ("2-Methylbutan-1-ol", "2-methylbutan-1-ol", 88),
           ("Prolin", "proline", 115), ("Phenylalaninmethylester", "phenylalanine methyl ester", 179),
           ("Citronellal", "citronellal", 154), ("Carvon", "carvone", 150), ("Limonen", "limonene", 136)]
_LABEL_NOUNS = [("Aldehyd", "aldehyde"), ("Keton", "ketone"), ("Amin", "amine"), ("Alkohol", "alcohol"),
                ("Ester", "ester"), ("Bromid", "bromide"), ("Iodid", "iodide"), ("Säure", "acid"), ("Alkin", "alkyne"),
                ("Olefin", "alkene"), ("Boronsäure", "boronic acid"), ("Verbindung", "compound"),
                ("Substrat", "substrate"), ("Startmaterial", "starting material"), ("Edukt", "starting material"),
                ("Sulfonamid", "sulfonamide"), ("Amid", "amide"), ("Aryliodid", "aryl iodide"),
                ("Arylbromid", "aryl bromide"), ("Sulfoniumsalz", "sulfonium salt"), ("Enon", "enone"),
                ("Diol", "diol"), ("Epoxid", "epoxide"), ("Azid", "azide"), ("Triflat", "triflate")]


def compound_label(rng: random.Random) -> str:
    n = rng.choice([rng.randint(1, 12), rng.randint(1, 40), rng.randint(1, 99)])
    return f"{n}{rng.choice(['', '', '', 'a', 'b', 'c', 'd', 'e', 'f'])}"


def systematic_name(rng: random.Random, lang: str) -> tuple[str, float]:
    if rng.random() < 0.18:
        de, en, m = rng.choice(_CHIRAL)
        return rng.choice(_STEREO) + (de if lang == "de" else en), float(m)
    parent_de, parent_en, m = rng.choice(_PARENT)
    picks = rng.sample(_SUBST, rng.choice([1, 1, 2]))
    locants = sorted(rng.sample([2, 3, 4, 5, 6], len(picks)))
    m += 60 * len(picks)
    if lang == "de":
        # "2-Brom-4-fluorbenzaldehyd": nur der erste Substituent groß
        subs = "-".join(f"{loc}-{s[0] if i == 0 else s[0].lower()}" for i, (loc, s) in enumerate(zip(locants, picks)))
        return subs + parent_de, float(m)
    subs = "-".join(f"{loc}-{s[1]}" for loc, s in zip(locants, picks))
    if parent_en.startswith("methyl "):
        return f"methyl {subs}{parent_en[len('methyl '):]}", float(m)   # "methyl 4-bromobenzoate"
    return subs + parent_en, float(m)


class NamePool:
    """Teilt Chemikalien stabil in Trainings- und Test-Namen (15 % nur im Test)."""

    def __init__(self, split: str):
        self.split = split

    @staticmethod
    def _is_test_only(key: str) -> bool:
        return int(hashlib.md5(key.encode()).hexdigest(), 16) % 100 < 15

    def allowed(self, key: str) -> bool:
        return self._is_test_only(key) == (self.split == "test")

    def pick(self, rng: random.Random, items: list[Chem]) -> Chem:
        options = [c for c in items if self.allowed(c.key)]
        return rng.choice(options or items)

    def filter_name(self, name: str, regenerate: Callable[[], str]) -> str:
        for _ in range(8):
            if self.allowed(name):
                return name
            name = regenerate()
        return name


def substrate(rng: random.Random, lang: str, pool: NamePool) -> tuple[str, float]:
    """Edukt: Datenbankname, systematischer Name, Nomen + Verbindungsnummer oder nur die Nummer."""
    r = rng.random()
    if r < 0.30:
        c = pool.pick(rng, REACTANTS)
        return c.name(rng, lang), c.M
    if r < 0.55:
        name, m = systematic_name(rng, lang)
        name = pool.filter_name(name, lambda: systematic_name(rng, lang)[0])
        if rng.random() < 0.3:
            name = f"{name} {compound_label(rng)}"
        return name, m
    if r < 0.80:
        noun = rng.choice(_LABEL_NOUNS)[0 if lang == "de" else 1]
        return f"{noun} {compound_label(rng)}", rng.uniform(120, 450)
    return compound_label(rng), rng.uniform(120, 450)


# ============================================================================
# Zahlen und Einheiten
# ============================================================================


@dataclass
class Ctx:
    rng: random.Random
    lang: str
    comma: bool                 # deutsches Dezimalkomma (pro Beispiel einheitlich)
    pool: NamePool
    n0: float                   # Stoffmenge des Leit-Reaktanden in mol
    vol_unit: str = "mL"
    eq_unit: str = "eq"

    @property
    def de(self) -> bool:
        return self.lang == "de"


def num(ctx: Ctx, value: float, digits: int | None = None) -> str:
    rng = ctx.rng
    if digits is None:
        if value < 1:
            digits = rng.choice([2, 3, 3])
        elif value < 10:
            digits = rng.choice([1, 2, 2])
        elif value < 100:
            digits = rng.choice([0, 1, 1])
        else:
            digits = rng.choice([0, 0, 1])
    s = f"{value:.{digits}f}"
    if "." in s and rng.random() < 0.35:
        s = s.rstrip("0").rstrip(".")
    if float(s) == 0:
        s = f"{value:.4f}".rstrip("0")
    return s.replace(".", ",") if ctx.comma else s


def mass_str(ctx: Ctx, grams: float) -> str:
    r = ctx.rng.random()
    if grams < 0.001:
        return f"{num(ctx, grams * 1e6)} µg"
    if grams < 1 and r < 0.85:
        return f"{num(ctx, grams * 1000)} mg"
    if grams >= 1000 and r < 0.6:
        return f"{num(ctx, grams / 1000)} kg"
    return f"{num(ctx, grams)} g"


def amount_str(ctx: Ctx, mol: float) -> str:
    r = ctx.rng.random()
    if mol < 0.001 and r < 0.6:
        return f"{num(ctx, mol * 1e6)} µmol"
    if mol >= 0.5 and r < 0.6:
        return f"{num(ctx, mol)} mol"
    return f"{num(ctx, mol * 1000)} mmol"


def volume_str(ctx: Ctx, ml: float) -> str:
    r = ctx.rng.random()
    if ml < 1 and r < 0.6:
        return f"{num(ctx, ml * 1000)} {'µL' if ctx.vol_unit == 'mL' else 'µl'}"
    if ml >= 500 and r < 0.6:
        return f"{num(ctx, ml / 1000)} {'L' if r < 0.4 else 'l'}"
    return f"{num(ctx, ml)} {ctx.vol_unit}"


EQ_UNITS_DE = ["eq", "eq.", "Äq.", "Äquiv.", "Eq.", "Äq", "Eq"]
EQ_UNITS_EN = ["equiv", "equiv.", "eq", "eq.", "equivalents", "Eq"]


def eq_str(ctx: Ctx, eq: float, allow_percent: bool = True) -> str:
    if allow_percent and eq < 0.3 and ctx.rng.random() < 0.85:
        pct = eq * 100
        p = f"{pct:.1f}".rstrip("0").rstrip(".") if pct < 10 else f"{pct:.0f}"
        if ctx.comma:
            p = p.replace(".", ",")
        return f"{p} {ctx.rng.choice(['mol%', 'mol%', 'mol%', 'mol-%'])}"
    digits = ctx.rng.choice([1, 1, 2, 2, 3]) if eq < 10 else 0
    value = num(ctx, eq, digits)
    unit = "equivalent" if ctx.eq_unit == "equivalents" and float(value.replace(",", ".")) == 1 else ctx.eq_unit
    return f"{value} {unit}"


def temperature(ctx: Ctx) -> str:
    rng = ctx.rng
    if rng.random() < 0.2:
        return rng.choice(["RT", "Raumtemperatur"]) if ctx.de else rng.choice(["room temperature", "rt", "RT"])
    return rng.choice(["-78", "-40", "-20", "-10", "0", "0", "25", "40", "60", "80", "100", "110", "120"]) + " °C"


def duration(ctx: Ctx) -> str:
    rng = ctx.rng
    if ctx.de:
        return rng.choice([f"{rng.choice([5, 10, 15, 20, 30, 45])} Minuten", f"{rng.choice([5, 10, 15, 30])} min",
                           f"{rng.choice([1, 2, 3, 4, 6, 12, 16, 24, 48])} h", f"{rng.choice([1, 2, 3, 5])} Stunden",
                           f"{rng.choice([2, 3])} Tage"])
    return rng.choice([f"{rng.choice([5, 10, 15, 20, 30, 45])} min", f"{rng.choice([1, 2, 3, 4, 6, 12, 16, 24, 48])} h",
                       f"{rng.choice([1, 2, 3, 5])} hours", f"{rng.choice([10, 30])} minutes"])


def flask(ctx: Ctx) -> tuple[str, str]:
    """Kolbenvolumen (NONE) und Kolbenwort."""
    v = ctx.rng.choice(["10 mL", "25 mL", "50 mL", "100 mL", "250 mL", "500 mL", "25 ml", "100 ml", "1 L", "2 L"])
    word = ctx.rng.choice(["Rundkolben", "Schlenkkolben", "Dreihalskolben", "Kolben", "Schlenkrohr"]) if ctx.de else \
        ctx.rng.choice(["round-bottom flask", "Schlenk flask", "flask", "vial", "Schlenk tube", "pressure tube"])
    return v, word


# ============================================================================
# Satz-Bausteine mit Zeichenbereichen
# ============================================================================

_GLUE_LEFT = {",", ".", ")", ";", ":", "]", "/"}
_GLUE_RIGHT = {"(", "[", "/"}


@dataclass
class Sentence:
    parts: list[tuple[str, str]] = field(default_factory=list)   # (Text, Label)

    def w(self, text: str, label: str = "NONE") -> "Sentence":
        """Wort(e) mit Label. Mehrere NONE-Wörter dürfen in einem String stehen."""
        if text:
            self.parts.append((text, label))
        return self

    def chem(self, text: str) -> "Sentence":
        return self.w(text, "CHEMICAL")

    def render(self) -> tuple[str, list[tuple[int, int, str]]]:
        out, spans, prev = "", [], ""
        for text, label in self.parts:
            glue = text in _GLUE_LEFT or prev in _GLUE_RIGHT or (text.startswith("-") and text[1:2].isalpha())
            if out and not glue:
                out += " "
            start = len(out)
            out += text
            if label != "NONE":
                spans.append((start, len(out), label))
            prev = text
        return out, spans


@dataclass
class Reagent:
    chem: Chem
    name: str
    eq: float
    mol: float

    @property
    def grams(self) -> float:
        return self.mol * self.chem.M

    @property
    def ml(self) -> float | None:
        if self.chem.solution:
            return self.mol / self.chem.solution[0] * 1000
        if self.chem.liquid and self.chem.d:
            return self.grams / self.chem.d
        return None


def make_reagent(ctx: Ctx, chem: Chem, eq: float | None = None) -> Reagent:
    rng = ctx.rng
    if eq is None:
        if chem.role in ("catalyst", "ligand"):
            eq = rng.choice([0.01, 0.02, 0.025, 0.05, 0.05, 0.1, 0.1, 0.15, 0.2])
        else:
            eq = rng.choice([1.0, 1.05, 1.1, 1.2, 1.5, 2.0, 2.5, 3.0, 5.0, 0.95])
    return Reagent(chem, chem.name(rng, ctx.lang), eq, ctx.n0 * eq)


def make_substrate(ctx: Ctx) -> Reagent:
    name, m = substrate(ctx.rng, ctx.lang, ctx.pool)
    return Reagent(Chem((name,), (name,), m, None, "reactant"), name, 1.0, ctx.n0)


def numbered_liquid(ctx: Ctx, eq: float) -> Reagent:
    """Verbindungsnummer als Flüssigkeit ("5.00 ml (48.0 mmol) von 7")."""
    label = compound_label(ctx.rng)
    return Reagent(Chem((label,), (label,), ctx.rng.uniform(100, 350), ctx.rng.uniform(0.85, 1.4), "reactant", True), label, eq, ctx.n0 * eq)


def quantity_items(ctx: Ctx, r: Reagent, *, want_volume: bool | None = None, eq_ok: bool = True) -> list[tuple[str, str]]:
    """Mengenangaben eines Reagenzes in zufälliger, aber typischer Auswahl und Reihenfolge."""
    rng = ctx.rng
    items: list[tuple[str, str]] = []
    vol = r.ml
    use_volume = vol is not None and (want_volume if want_volume is not None else rng.random() < 0.7)
    if use_volume:
        items.append((volume_str(ctx, vol), "VOLUME"))
    if (not use_volume or rng.random() < 0.35) and (r.chem.role not in ("catalyst", "ligand") or rng.random() < 0.8):
        items.append((mass_str(ctx, r.grams), "MASS"))
    if rng.random() < 0.85 or not items:
        items.append((amount_str(ctx, r.mol), "AMOUNT"))
    if eq_ok and rng.random() < 0.8:
        eq = (eq_str(ctx, r.eq), "EQ")
        if rng.random() < 0.15 and len(items) > 1:
            items.insert(len(items) - 1, eq)   # "3.97 g, 1.20 eq, 36.5 mmol" wie im Benchmark
        else:
            items.append(eq)
    return items


def add_group(s: Sentence, items: list[tuple[str, str]], ctx: Ctx, prefix: list[tuple[str, str]] | None = None) -> None:
    sep = ";" if ctx.rng.random() < 0.05 else ","
    s.w("(")
    for i, (t, l) in enumerate((prefix or []) + items):
        if i:
            s.w(sep)
        s.w(t, l)
    s.w(")")


def name_first(s: Sentence, ctx: Ctx, r: Reagent, **kw) -> None:
    """'benzaldehyde (1.06 g, 10.0 mmol, 1.0 equiv)'"""
    s.chem(r.name)
    add_group(s, quantity_items(ctx, r, **kw), ctx)


def quantities_first(s: Sentence, ctx: Ctx, r: Reagent, of_word: bool = False) -> None:
    """'6.55 ml (46.5 mmol, 0.95 eq) Diisopropylamin' oder '4.0 mL (10 mmol) of n-BuLi'"""
    items = quantity_items(ctx, r)
    s.w(*items[0])
    if items[1:]:
        add_group(s, items[1:], ctx)
    if of_word:
        s.w("von" if ctx.de else "of")
    s.chem(r.name)


def bare_list(s: Sentence, ctx: Ctx, r: Reagent, name_last: bool = True) -> None:
    """Benchmark-Stil ohne Klammern: '102.26 g 0.587 mol 0.91 equiv DEAD'"""
    if not name_last:
        s.chem(r.name)
    for t, l in quantity_items(ctx, r):
        s.w(t, l)
    if name_last:
        s.chem(r.name)


def solution_reagent(s: Sentence, ctx: Ctx, r: Reagent) -> None:
    """Reagenz als Lösung; Konzentration und Trägerlösemittel sind NONE."""
    rng = ctx.rng
    c, solv_de, solv_en = r.chem.solution
    conc = num(ctx, c, 1)
    vol = volume_str(ctx, r.ml)
    eq_item = [(eq_str(ctx, r.eq), "EQ")] if rng.random() < 0.75 else []
    if ctx.de:
        if rng.random() < 0.5:
            s.w(vol, "VOLUME")
            add_group(s, [(amount_str(ctx, r.mol), "AMOUNT")] + eq_item, ctx)
            s.w(f"einer {conc} M")
            s.chem(r.name)
            s.w("-Lösung" if rng.random() < 0.6 else "")
            if rng.random() < 0.4:
                s.w(f"in {solv_de}")
        else:
            s.chem(r.name)
            add_group(s, [(vol, "VOLUME"), (amount_str(ctx, r.mol), "AMOUNT")] + eq_item, ctx,
                      prefix=[(f"{conc} M in {solv_de}", "NONE")])
    else:
        if rng.random() < 0.6:
            s.chem(r.name)
            add_group(s, [(vol, "VOLUME"), (amount_str(ctx, r.mol), "AMOUNT")] + eq_item, ctx,
                      prefix=[(f"{conc} M in {solv_en}", "NONE")])
        else:
            s.w(f"a {conc} M solution of")
            s.chem(r.name)
            s.w(f"in {solv_en}")
            add_group(s, [(vol, "VOLUME"), (amount_str(ctx, r.mol), "AMOUNT")] + eq_item, ctx)


def solvent_phrase(s: Sentence, ctx: Ctx, *, paren: bool | None = None) -> None:
    rng = ctx.rng
    solv = ctx.pool.pick(rng, SOLVENTS)
    name = solv.name(rng, ctx.lang)
    vol = volume_str(ctx, rng.choice([0.5, 1, 2, 3, 5, 8, 10, 15, 20, 25, 40, 50, 100, 150, 250, 1000]))
    adj = ""
    if rng.random() < 0.3:
        adj = rng.choice(["trockenem", "abs.", "wasserfreiem", "entgastem", "frisch destilliertem"]) if ctx.de else \
            rng.choice(["dry", "anhydrous", "degassed", "freshly distilled"])
    if paren if paren is not None else rng.random() < 0.5:
        s.w(adj)
        s.chem(name)
        alias = solv.en[-1]
        if not ctx.de and alias != name and rng.random() < 0.25:
            add_group(s, [(vol, "VOLUME")], ctx, prefix=[(alias, "CHEMICAL")])
        else:
            extra = [(f"{num(ctx, rng.choice([0.05, 0.1, 0.2, 0.5]), 2)} M", "NONE")] if rng.random() < 0.1 else []
            add_group(s, [(vol, "VOLUME")] + extra, ctx)
    else:
        s.w(vol, "VOLUME")
        s.w(adj)
        s.chem(name)


# ============================================================================
# Sätze mit Ansatzgrößen (deutsch)
# ============================================================================


def de_vorgelegt(ctx: Ctx) -> Sentence:
    rng = ctx.rng
    s = Sentence().w(rng.choice(["Zunächst wurden", "Es wurden", "In einem ausgeheizten Kolben wurden", "Unter Argon wurden"]))
    r = numbered_liquid(ctx, 1.0) if rng.random() < 0.3 else make_reagent(ctx, ctx.pool.pick(rng, LIQUID_REAGENTS), rng.choice([0.95, 1.0, 1.1]))
    quantities_first(s, ctx, r)
    s.w("in")
    solvent_phrase(s, ctx, paren=False)
    return s.w("vorgelegt").w(".")


def de_geloest(ctx: Ctx) -> Sentence:
    rng = ctx.rng
    s = Sentence()
    name_first(s, ctx, make_substrate(ctx))
    s.w(rng.choice(["wurde in", "wurde unter Argon in", "wurden in"]))
    solvent_phrase(s, ctx)
    s.w(rng.choice(["gelöst", f"gelöst und auf {temperature(ctx)} gekühlt", "suspendiert", "vorgelegt"]))
    return s.w(".")


def de_zu_loesung(ctx: Ctx) -> Sentence:
    rng = ctx.rng
    s = Sentence().w(rng.choice(["Zu einer Lösung von", "Zu einer Lösung aus", "Zu einer Suspension von"]))
    name_first(s, ctx, make_substrate(ctx))
    s.w("in")
    solvent_phrase(s, ctx)
    s.w(rng.choice(["wurde", "wurden"]) + (f" bei {temperature(ctx)}" if rng.random() < 0.6 else ""))
    reagent = make_reagent(ctx, ctx.pool.pick(rng, REAGENTS + ORGANOMETALLICS))
    if reagent.chem.solution and rng.random() < 0.6:
        solution_reagent(s, ctx, reagent)
    else:
        name_first(s, ctx, reagent)
    s.w(rng.choice(["langsam zugetropft", "tropfenweise zugegeben", "portionsweise zugegeben", "zugegeben", "addiert", "hinzugefügt"]))
    return s.w(".")


def de_loesung_zugetropft(ctx: Ctx) -> Sentence:
    rng = ctx.rng
    s = Sentence()
    if rng.random() < 0.6:
        s.w(rng.choice(["Die Lösung wurde auf", "Das Gemisch wurde auf"]) + f" {temperature(ctx)} " + rng.choice(["abgekühlt und", "gekühlt und", "gebracht und"]))
    else:
        s.w(rng.choice(["Anschließend wurden", "Danach wurden", f"Bei {temperature(ctx)} wurden"]))
    solution_reagent(s, ctx, make_reagent(ctx, ctx.pool.pick(rng, ORGANOMETALLICS)))
    s.w(rng.choice(["zugegeben", "zugetropft", "langsam zugetropft", f"über {duration(ctx)} zugetropft"]))
    return s.w(".")


def de_direkt_addiert(ctx: Ctx) -> Sentence:
    rng = ctx.rng
    s = Sentence().w(f"Die Lösung wurde auf {temperature(ctx)} abgekühlt und anschließend" if rng.random() < 0.6 else rng.choice(["Danach wurden", "Dann wurden"]))
    r = make_reagent(ctx, ctx.pool.pick(rng, LIQUID_REAGENTS))
    s.w(volume_str(ctx, r.ml), "VOLUME") if r.ml is not None else s.w(mass_str(ctx, r.grams), "MASS")
    s.chem(r.name)
    return s.w(rng.choice(["addiert", "zugegeben", "hinzugegeben"])).w(".")


def de_nummer_als_loesung(ctx: Ctx) -> Sentence:
    rng = ctx.rng
    s = Sentence().w(f"Nach {duration(ctx)} wurden" if rng.random() < 0.7 else "Anschließend wurden")
    r = numbered_liquid(ctx, rng.choice([1.0, 1.1, 1.2, 1.5]))
    items = quantity_items(ctx, r, want_volume=True)
    s.w(*items[0])
    if items[1:]:
        add_group(s, items[1:], ctx)
    s.w("von")
    s.chem(r.name)
    solv = ctx.pool.pick(rng, SOLVENTS).de[-1]
    s.w(f"als {solv}-Lösung" if rng.random() < 0.7 else f"in {solv}")
    return s.w(rng.choice(["zugetropft", "langsam zugetropft", "zugegeben"])).w(".")


def de_nummer_direkt(ctx: Ctx) -> Sentence:
    rng = ctx.rng
    s = Sentence().w(f"Nach weiteren {duration(ctx)} wurde" if rng.random() < 0.6 else "Dann wurden")
    quantities_first(s, ctx, numbered_liquid(ctx, rng.choice([0.9, 1.0, 1.1, 1.2])))
    s.w(f"addiert und die Lösung für {duration(ctx)} gerührt" if rng.random() < 0.6 else "zugegeben")
    return s.w(".")


def de_klammerlos(ctx: Ctx) -> Sentence:
    """Benchmark-Stil: 'In einem Kolben wurden 102.26 g 0.587 mol 0.91 equiv DEAD vorgelegt.'"""
    rng = ctx.rng
    v, word = flask(ctx)
    s = Sentence().w(rng.choice([f"In einem {v} {word} wurden", "In einem Kolben wurden", "Es wurden",
                                 "Zu dieser Lösung wurden langsam", "Als Letztes wurde"]))
    bare_list(s, ctx, make_substrate(ctx) if rng.random() < 0.5 else make_reagent(ctx, ctx.pool.pick(rng, REAGENTS)),
              name_last=rng.random() < 0.8)
    if rng.random() < 0.5:
        s.w("in")
        solvent_phrase(s, ctx, paren=False)
    return s.w(rng.choice(["vorgelegt", "gelöst", "zugegeben", "hinzugegeben", "eingewogen"])).w(".")


def de_zwei_komponenten(ctx: Ctx) -> Sentence:
    rng = ctx.rng
    s = Sentence()
    name_first(s, ctx, make_substrate(ctx))
    s.w(rng.choice(["und", "sowie"]))
    name_first(s, ctx, make_reagent(ctx, ctx.pool.pick(rng, SOLID_REAGENTS + HYDRATES)))
    s.w("wurden in")
    solvent_phrase(s, ctx)
    return s.w(rng.choice(["gelöst", "suspendiert", "vorgelegt", "kombiniert"])).w(".")


def de_katalysator(ctx: Ctx) -> Sentence:
    rng = ctx.rng
    s = Sentence().w(rng.choice(["Anschließend wurden", "Unter Argon wurden", "Dann wurden"]))
    cat = make_reagent(ctx, ctx.pool.pick(rng, CATS))
    s.chem(cat.name)
    add_group(s, ([(mass_str(ctx, cat.grams), "MASS")] if rng.random() < 0.8 else []) + [(eq_str(ctx, cat.eq), "EQ")], ctx)
    if rng.random() < 0.6:
        lig = make_reagent(ctx, ctx.pool.pick(rng, LIGANDS), cat.eq * rng.choice([1, 2]))
        s.w("und")
        s.chem(lig.name)
        add_group(s, [(mass_str(ctx, lig.grams), "MASS"), (eq_str(ctx, lig.eq), "EQ")], ctx)
    return s.w("zugegeben").w(".")


def de_versetzt(ctx: Ctx) -> Sentence:
    rng = ctx.rng
    s = Sentence().w(rng.choice(["Das Gemisch wurde mit", "Die Reaktionslösung wurde mit", f"Die Mischung wurde bei {temperature(ctx)} mit"]))
    name_first(s, ctx, make_reagent(ctx, ctx.pool.pick(rng, REAGENTS + HYDRATES)))
    s.w(rng.choice(["versetzt", f"versetzt und {duration(ctx)} bei {temperature(ctx)} gerührt", "behandelt"]))
    return s.w(".")


def de_iod_zink(ctx: Ctx) -> Sentence:
    """Benchmark-Stil: '2.54 g 10.0 mmol 1.00 Eq Iod wurden in 30 mL Ethanol gelöst und mit … versetzt.'"""
    rng = ctx.rng
    s = Sentence()
    bare_list(s, ctx, make_substrate(ctx) if rng.random() < 0.5 else make_reagent(ctx, ctx.pool.pick(rng, REAGENTS), 1.0))
    s.w("wurden in")
    solvent_phrase(s, ctx, paren=False)
    s.w("gelöst und mit")
    bare_list(s, ctx, make_reagent(ctx, ctx.pool.pick(rng, REAGENTS)))
    return s.w("versetzt").w(".")


def de_gemisch_loesemittel(ctx: Ctx) -> Sentence:
    rng = ctx.rng
    s = Sentence()
    name_first(s, ctx, make_substrate(ctx))
    s.w("wurde in einem Gemisch aus")
    solvent_phrase(s, ctx, paren=True)
    s.w("und")
    solvent_phrase(s, ctx, paren=True)
    return s.w(rng.choice(["gelöst", "aufgenommen"])).w(".")


# ============================================================================
# Sätze mit Ansatzgrößen (englisch)
# ============================================================================


def en_to_solution(ctx: Ctx) -> Sentence:
    rng = ctx.rng
    s = Sentence().w(rng.choice(["To a solution of", "To a stirred solution of", "To a suspension of"]))
    name_first(s, ctx, make_substrate(ctx))
    s.w("in")
    solvent_phrase(s, ctx)
    s.w(rng.choice(["was added", "were added", "was added dropwise", "was added portionwise"]) + (f" at {temperature(ctx)}" if rng.random() < 0.3 else ""))
    reagent = make_reagent(ctx, ctx.pool.pick(rng, REAGENTS + ORGANOMETALLICS))
    if reagent.chem.solution and rng.random() < 0.6:
        solution_reagent(s, ctx, reagent)
    else:
        name_first(s, ctx, reagent)
    if rng.random() < 0.5:
        s.w(f"at {temperature(ctx)}")
    return s.w(".")


def en_sequential(ctx: Ctx) -> Sentence:
    """'Aryl sulfonium salt (0.2 mmol), 5CzBN (5 mol%), KSeCN (87 mg, 3 equiv.), and ethyl acetate (EtOAc, 2.0 mL) were …'"""
    rng = ctx.rng
    s = Sentence()
    sub = make_substrate(ctx)
    s.chem(sub.name)
    add_group(s, [(amount_str(ctx, sub.mol), "AMOUNT")] + ([(mass_str(ctx, sub.grams), "MASS")] if rng.random() < 0.3 else []), ctx)
    s.w(",")
    cat = make_reagent(ctx, ctx.pool.pick(rng, CATS))
    s.chem(cat.name)
    add_group(s, [(eq_str(ctx, cat.eq), "EQ")], ctx)
    s.w(",")
    reagent = make_reagent(ctx, ctx.pool.pick(rng, SOLID_REAGENTS))
    s.chem(reagent.name)
    add_group(s, [(mass_str(ctx, reagent.grams), "MASS"), (eq_str(ctx, reagent.eq, allow_percent=False), "EQ")], ctx)
    s.w(",").w("and")
    solv = ctx.pool.pick(rng, SOLVENTS)
    s.chem(solv.en[0])
    vol = volume_str(ctx, rng.choice([1, 2, 3, 5, 10]))
    if len(solv.en) > 1 and rng.random() < 0.6:
        add_group(s, [(vol, "VOLUME")], ctx, prefix=[(solv.en[-1], "CHEMICAL")])
    else:
        add_group(s, [(vol, "VOLUME")], ctx)
    v, word = flask(ctx)
    return s.w(rng.choice(["were sequentially introduced into a", "were added to a", "were charged into a"]) + f" {v} {word}").w(".")


def en_charged(ctx: Ctx) -> Sentence:
    rng = ctx.rng
    v, word = flask(ctx)
    s = Sentence().w(rng.choice([f"A flame-dried {v} {word} was charged with", f"An oven-dried {word} was charged with", "A flask was charged with"]))
    name_first(s, ctx, make_substrate(ctx))
    if rng.random() < 0.5:
        s.w(",")
    s.w("and")
    name_first(s, ctx, make_reagent(ctx, ctx.pool.pick(rng, SOLID_REAGENTS + CATS + HYDRATES)))
    return s.w(".")


def en_solution_dropwise(ctx: Ctx) -> Sentence:
    rng = ctx.rng
    s = Sentence()
    if rng.random() < 0.4:
        s.w(f"The mixture was cooled to {temperature(ctx)}, and")
    solution_reagent(s, ctx, make_reagent(ctx, ctx.pool.pick(rng, ORGANOMETALLICS)))
    s.w(rng.choice(["was added dropwise", f"was added dropwise over {duration(ctx)}", "was slowly added", "was added via syringe"]))
    return s.w(".")


def en_volume_of(ctx: Ctx) -> Sentence:
    rng = ctx.rng
    s = Sentence().w(rng.choice(["To the mixture were added", "Then,", "Subsequently,"]))
    quantities_first(s, ctx, make_reagent(ctx, ctx.pool.pick(rng, LIQUID_REAGENTS)), of_word=True)
    s.w(rng.choice(["dropwise", "was added", "was added dropwise", "was added in one portion"]))
    return s.w(".")


def en_dissolved_treated(ctx: Ctx) -> Sentence:
    rng = ctx.rng
    s = Sentence()
    name_first(s, ctx, make_substrate(ctx))
    s.w("was dissolved in")
    solvent_phrase(s, ctx, paren=False)
    s.w("and treated with")
    cat = make_reagent(ctx, ctx.pool.pick(rng, CATS))
    s.chem(cat.name)
    add_group(s, [(mass_str(ctx, cat.grams), "MASS"), (eq_str(ctx, cat.eq), "EQ")], ctx)
    if cat.name.endswith("Pd/C") or rng.random() < 0.2:
        s.w("under 1 atm")
        s.chem("H2")
    return s.w(f"for {duration(ctx)}").w(".")


def en_bare(ctx: Ctx) -> Sentence:
    """Benchmark-Stil: 'L-Proline 115 mg 1.00 mmol 20 mol% and ethylenediamine 301 mg … were combined in 8 mL ethanol'"""
    rng = ctx.rng
    s = Sentence()
    bare_list(s, ctx, make_substrate(ctx), name_last=False)
    s.w("and")
    bare_list(s, ctx, make_reagent(ctx, ctx.pool.pick(rng, REAGENTS + CATS)), name_last=False)
    s.w(rng.choice(["were combined in", "were dissolved in", "were suspended in"]))
    solvent_phrase(s, ctx, paren=False)
    if rng.random() < 0.6:
        s.w(f"at {temperature(ctx)}")
    return s.w(".")


def en_solution_treated(ctx: Ctx) -> Sentence:
    rng = ctx.rng
    s = Sentence().w("A solution of")
    name_first(s, ctx, make_reagent(ctx, ctx.pool.pick(rng, SOLID_REAGENTS)))
    s.w("in")
    solvent_phrase(s, ctx, paren=False)
    s.w("was treated with")
    name_first(s, ctx, make_substrate(ctx))
    return s.w(f"at {temperature(ctx)}").w(".")


def en_catalyst(ctx: Ctx) -> Sentence:
    rng = ctx.rng
    s = Sentence()
    cat = make_reagent(ctx, ctx.pool.pick(rng, CATS))
    s.chem(cat.name)
    add_group(s, ([(mass_str(ctx, cat.grams), "MASS")] if rng.random() < 0.8 else []) + [(eq_str(ctx, cat.eq), "EQ")], ctx)
    s.w("and")
    lig = make_reagent(ctx, ctx.pool.pick(rng, LIGANDS), cat.eq * rng.choice([1, 2]))
    s.chem(lig.name)
    add_group(s, [(mass_str(ctx, lig.grams), "MASS"), (eq_str(ctx, lig.eq), "EQ")], ctx)
    return s.w(rng.choice(["were added under argon", "were added", "were added in one portion"])).w(".")


def en_mixture_solvents(ctx: Ctx) -> Sentence:
    rng = ctx.rng
    s = Sentence()
    name_first(s, ctx, make_substrate(ctx))
    s.w("and")
    name_first(s, ctx, make_reagent(ctx, ctx.pool.pick(rng, SOLID_REAGENTS + HYDRATES)))
    a, b = ctx.pool.pick(rng, SOLVENTS), ctx.pool.pick(rng, SOLVENTS)
    s.w("were dissolved in a mixture of")
    s.chem(a.en[-1]).w("/").chem(b.en[-1])
    add_group(s, [(f"{rng.choice([1, 2, 3, 4, 9])}:1", "NONE"), (volume_str(ctx, rng.choice([2, 5, 10, 20])), "VOLUME")], ctx)
    return s.w(".")


# ============================================================================
# Sätze ohne Ansatzgrößen (alles NONE): Bedingungen, Aufarbeitung, Produkt
# ============================================================================


def de_bedingungen(ctx: Ctx) -> Sentence:
    rng = ctx.rng
    return Sentence().w(rng.choice([
        f"Die Reaktionsmischung wurde {duration(ctx)} bei {temperature(ctx)} gerührt.",
        f"Das Gemisch wurde auf {temperature(ctx)} erwärmt und {duration(ctx)} gerührt.",
        "Der Reaktionsfortschritt wurde per DC kontrolliert.",
        f"Nach {duration(ctx)} wurde die Lösung auf Raumtemperatur erwärmt.",
        f"Die Suspension wurde unter Wasserstoffatmosphäre (1 bar) für {duration(ctx)} gerührt.",
        f"Die Lösung wurde für {duration(ctx)} unter Rückfluss erhitzt.",
        "Die Reaktion wurde unter Argon-Atmosphäre durchgeführt.",
    ]))


def de_aufarbeitung(ctx: Ctx) -> Sentence:
    rng = ctx.rng
    solv = ctx.pool.pick(rng, SOLVENTS).name(rng, "de")
    v = volume_str(ctx, rng.choice([5, 10, 20, 30, 50, 100]))
    label, m = compound_label(rng), mass_str(ctx, rng.uniform(0.02, 3))
    return Sentence().w(rng.choice([
        f"Die wässrige Phase wurde dreimal mit je {v} {solv} extrahiert.",
        f"Die vereinigten organischen Phasen wurden mit {v} ges. NaCl-Lösung gewaschen, über Na2SO4 getrocknet und unter vermindertem Druck eingeengt.",
        f"Die organische Phase wurde mit {v} {solv} gewaschen.",
        f"Gewaschen wurde mit {v} {solv}.",
        f"Die Reaktion wurde durch Zugabe von {v} ges. NH4Cl-Lösung beendet.",
        f"Das Rohprodukt wurde säulenchromatographisch gereinigt (SiO2, {solv}/EtOAc {rng.choice([4, 9, 19])}:1).",
        f"Man erhielt {label} ({m}, {rng.randint(40, 98)} %) als {rng.choice(['farblosen Feststoff', 'gelbes Öl', 'weißen Feststoff'])}.",
        f"Nach Filtration über Celite wurde das Lösungsmittel entfernt und {m} {label} erhalten.",
        f"Der Rückstand wurde aus {solv} umkristallisiert.",
    ]))


def en_conditions(ctx: Ctx) -> Sentence:
    rng = ctx.rng
    return Sentence().w(rng.choice([
        f"The reaction mixture was stirred at {temperature(ctx)} for {duration(ctx)}.",
        "The progress of the reaction was monitored by TLC.",
        f"After {duration(ctx)}, the mixture was allowed to warm to room temperature.",
        f"The mixture was heated to reflux for {duration(ctx)}.",
        "The flask was evacuated and backfilled with argon three times.",
        f"The vial was sealed and irradiated with blue LEDs (450 nm) for {duration(ctx)}.",
    ]))


def en_workup(ctx: Ctx) -> Sentence:
    rng = ctx.rng
    solv = ctx.pool.pick(rng, SOLVENTS).name(rng, "en")
    v = volume_str(ctx, rng.choice([5, 10, 20, 30, 50, 100]))
    label, m = compound_label(rng), mass_str(ctx, rng.uniform(0.02, 3))
    return Sentence().w(rng.choice([
        f"The aqueous layer was extracted with {solv} (3 × {v}).",
        f"The combined organic layers were washed with brine ({v}), dried over Na2SO4, filtered and concentrated under reduced pressure.",
        f"The mixture was extracted with {v} {solv}.",
        f"The reaction was quenched by addition of {v} water.",
        f"The reaction was quenched with sat. aq. NH4Cl ({v}).",
        f"The mixture was diluted with {solv} ({v}) and washed with water ({v}).",
        f"The residue was purified by flash column chromatography (SiO2, hexanes/EtOAc {rng.choice([4, 9, 19])}:1) to afford {label} ({m}, {rng.randint(40, 98)}%) as a white solid.",
        f"Purification by column chromatography afforded {label} ({m}, {rng.randint(40, 98)}% yield).",
    ]))


REACTION_DE = [de_vorgelegt, de_geloest, de_zu_loesung, de_loesung_zugetropft, de_direkt_addiert,
               de_nummer_als_loesung, de_nummer_direkt, de_klammerlos, de_zwei_komponenten, de_katalysator,
               de_versetzt, de_iod_zink, de_gemisch_loesemittel]
REACTION_EN = [en_to_solution, en_sequential, en_charged, en_solution_dropwise, en_volume_of, en_dissolved_treated,
               en_bare, en_solution_treated, en_catalyst, en_mixture_solvents]
NONE_DE = [de_bedingungen, de_aufarbeitung]
NONE_EN = [en_conditions, en_workup]


# ============================================================================
# Beispiel = Absatz aus 1–3 Sätzen
# ============================================================================


@dataclass
class RawExample:
    id: str
    language: str
    text: str
    spans: list[tuple[int, int, str]]
    frames: list[str]


def generate_raw(rng: random.Random, lang: str, pool: NamePool) -> RawExample:
    ctx = Ctx(rng=rng, lang=lang, comma=(lang == "de" and rng.random() < 0.4), pool=pool,
              n0=math.exp(rng.uniform(math.log(5e-5), math.log(0.2))),
              vol_unit=rng.choice(["mL", "ml"]) if lang == "de" else rng.choice(["mL", "mL", "ml"]),
              eq_unit=rng.choice(EQ_UNITS_DE if lang == "de" else EQ_UNITS_EN))
    reaction = REACTION_DE if lang == "de" else REACTION_EN
    neutral = NONE_DE if lang == "de" else NONE_EN
    n_sent = rng.choices([1, 2, 3], weights=[45, 35, 20])[0]
    text, spans, frames = "", [], []
    for i in range(n_sent):
        use_neutral = (i > 0 and rng.random() < 0.3) or (n_sent == 1 and rng.random() < 0.12)
        frame = rng.choice(neutral if use_neutral else reaction)
        sent_text, sent_spans = frame(ctx).render()
        # Satzanfang groß ("Lithium aluminum hydride …"), aber "n-BuLi", "(S)-BINOL", "4-…" bleiben
        if sent_text[:1].islower() and not re.match(r"^[a-z]{1,4}-", sent_text):
            sent_text = sent_text[0].upper() + sent_text[1:]
        offset = len(text) + (1 if text else 0)
        text = f"{text} {sent_text}" if text else sent_text
        spans.extend((s + offset, e + offset, l) for s, e, l in sent_spans)
        frames.append(frame.__name__)
    return RawExample(hashlib.sha256(text.encode("utf-8")).hexdigest()[:16], lang, text, spans, frames)


# ============================================================================
# Tokenisierung: NLTagger (wie die App) und Benchmark-Stil
# ============================================================================


def tokenizer_binary() -> Path:
    """Baut nl_tokenizer.swift zusammen mit dem Normalizer der App (nur wenn sich die Quellen geändert haben).
    Das Binary liegt im temporären Verzeichnis, nicht im Projekt."""
    sources = [ROOT / "nl_tokenizer.swift",
               ROOT.parent / "macos/ChemJournal/Services/SmartExtract/SynthesisTextNormalizer.swift",
               ROOT.parent / "macos/ChemJournal/Services/SmartExtract/SynthesisLexicon.swift"]
    digest = hashlib.sha256(b"".join(p.read_bytes() for p in sources)).hexdigest()[:12]
    binary = Path(tempfile.gettempdir()) / f"chemjournal_nl_tokenizer_{digest}"
    if not binary.exists():
        print(f"Baue Swift-Tokenizer ({binary.name}) …", flush=True)
        subprocess.run(["swiftc", "-O", *map(str, sources), "-o", str(binary)], check=True)
    return binary


def nl_tokenize(texts: dict[str, str]) -> dict[str, tuple[str, list[tuple[int, int]]]]:
    """id → (normalisierter Text, Token-Offsets). Ein Prozessaufruf für alle Texte."""
    payload = "".join(json.dumps({"id": k, "text": v}, ensure_ascii=False) + "\n" for k, v in texts.items())
    proc = subprocess.run([str(tokenizer_binary()), MODEL_LANGUAGE], input=payload.encode("utf-8"),
                          capture_output=True, check=True)
    out = {}
    for line in proc.stdout.decode("utf-8").splitlines():
        rec = json.loads(line)
        out[rec["id"]] = (rec["normalized"], [tuple(t) for t in rec["tokens"]])
    return out


def label_tokens(text: str, spans, offsets) -> tuple[list[str], list[str]] | None:
    """Vergibt jedem Token das Label seiner Zeichen. `None`, wenn ein Token eine Labelgrenze kreuzt."""
    char_labels = ["NONE"] * len(text)
    for s, e, l in spans:
        char_labels[s:e] = [l] * (e - s)
    tokens, labels = [], []
    for s, e in offsets:
        token_labels = {char_labels[i] for i in range(s, e) if not text[i].isspace()}
        if len(token_labels) == 2 and "NONE" in token_labels:
            # NLTagger hängt einen Satzpunkt manchmal an das Wort ("H2O."): Label des Wortes übernehmen
            if all(char_labels[i] != "NONE" or text[i] in ".,;:" for i in range(s, e)):
                token_labels.discard("NONE")
        if len(token_labels) != 1:
            return None
        tokens.append(text[s:e])
        labels.append(token_labels.pop())
    return tokens, labels


_KEEP_PERIOD = {"abs.", "ges.", "aq.", "sat.", "equiv.", "eq.", "Äq.", "Äquiv.", "Eq."}


def legacy_tokenize(ex: RawExample, rng: random.Random) -> tuple[list[str], list[str]]:
    """Token-Stil der goldenen Benchmarks: Leerzeichen trennen, Klammern/Kommata sind eigene Tokens,
    Entitäten teils als ein Token ("3.50 g", "Trimethylsilylchlorid 4") oder ohne Leerzeichen ("298.0mg")."""
    tokens: list[str] = []
    labels: list[str] = []

    def push_plain(chunk: str) -> None:
        for word in chunk.split():
            lead, trail = [], []
            while word and word[0] in "([":
                lead.append(word[0]); word = word[1:]
            while word and (word[-1] in ",;:)]" or (word[-1] == "." and word not in _KEEP_PERIOD)):
                trail.insert(0, word[-1]); word = word[:-1]
            for t in lead + ([word] if word else []) + trail:
                tokens.append(t); labels.append("NONE")

    pos = 0
    for s, e, l in sorted(ex.spans):
        push_plain(ex.text[pos:s])
        span_text = ex.text[s:e]
        r = rng.random()
        if " " in span_text and r < 0.35:
            tokens.append(span_text); labels.append(l)
        elif l != "CHEMICAL" and " " in span_text and r < 0.5:
            tokens.append(span_text.replace(" ", "")); labels.append(l)
        else:
            for w in span_text.split():
                tokens.append(w); labels.append(l)
        pos = e
    push_plain(ex.text[pos:])
    return tokens, labels


# ============================================================================
# Datensatz
# ============================================================================


@dataclass
class BuildStats:
    generated: int = 0
    normalizer_changed: int = 0
    boundary_conflicts: int = 0
    duplicates: int = 0
    changed_examples: list[str] = field(default_factory=list)


class SmartExtractDatasetBuilder:
    def __init__(self, seed: int = 1337, legacy_share: float = 0.2):
        self.seed = seed
        self.legacy_share = legacy_share
        self.seen: set[str] = set()
        self.stats = BuildStats()

    def build_split(self, split: str, count: int, de_ratio: float = 0.5) -> list[dict]:
        """Erzeugt `count` Beispiele für `split` ("train", "val", "test"). Splits teilen keine Texte."""
        rng = random.Random(f"{self.seed}-{split}")
        pool = NamePool("test" if split == "test" else "train")
        result: list[dict] = []
        while len(result) < count:
            batch = []
            for _ in range(int((count - len(result)) * 1.15) + 10):
                ex = generate_raw(rng, "de" if rng.random() < de_ratio else "en", pool)
                self.stats.generated += 1
                if ex.id in self.seen:
                    self.stats.duplicates += 1
                    continue
                self.seen.add(ex.id)
                batch.append(ex)
            tokenized = nl_tokenize({ex.id: ex.text for ex in batch})
            for ex in batch:
                normalized, offsets = tokenized[ex.id]
                if normalized != ex.text:
                    # Der Generator muss genau den Text liefern, den die App nach der Normalisierung sieht
                    self.stats.normalizer_changed += 1
                    if len(self.stats.changed_examples) < 5:
                        self.stats.changed_examples.append(f"{ex.text}\n   → {normalized}")
                    continue
                if rng.random() < self.legacy_share:
                    tokens, labels = legacy_tokenize(ex, rng)
                    style = "legacy"
                else:
                    labelled = label_tokens(ex.text, ex.spans, offsets)
                    if labelled is None:
                        self.stats.boundary_conflicts += 1
                        continue
                    tokens, labels = labelled
                    style = "nl"
                result.append({"id": ex.id, "language": ex.language, "raw_text": ex.text, "tokenization": style,
                               "frames": ex.frames, "tokens": tokens, "labels": labels})
                if len(result) == count:
                    break
        return result


if __name__ == "__main__":
    # Schnellansicht: python3 dataset_builder.py [seed]
    b = SmartExtractDatasetBuilder(seed=int(sys.argv[1]) if len(sys.argv) > 1 else 7)
    for item in b.build_split("train", 8):
        print(f"[{item['language']}/{item['tokenization']}] {item['raw_text']}")
        print("   ", " ".join(f"{t}/{l[:4]}" if l != "NONE" else t for t, l in zip(item["tokens"], item["labels"])))
    print(b.stats)
