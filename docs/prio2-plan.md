# CapCut MCP — Prio 2: Keyframes, Masken, Duplikate & Clip-Info

> Status: **Geplant, noch nicht implementiert**
> Voraussetzung: Prio 1 ist fertig (commit `3f77873`)

---

## Uebersicht

| # | Tool | Aufwand | Status |
|---|------|---------|--------|
| 1 | `get_clip_info` | Klein | Bereit zur Implementierung |
| 2 | `duplicate_clip` | Mittel | Bereit zur Implementierung |
| 3 | `add_keyframe` | Gross | **Braucht Reverse-Engineering** |
| 4 | `add_mask` | Gross | **Braucht Reverse-Engineering** |

---

## 1. `get_clip_info` — Bereit

Gibt alle Properties eines einzelnen Segments strukturiert zurueck.

```
Input:  project_id (string), clip_id (string)
Output: Formatierter Text mit allen Segment-Properties
```

### Implementierung

Nutzt `TimelineHelper.find_segment/2`, formatiert das Segment als lesbaren Text.
Zeigt: transform, opacity, volume, loop, speed, source/target timerange, material_id,
extra_material_refs, visible, reverse.

### Felder eines echten Video-Segments (Projekt 0404)

```
clip:                 {alpha, flip, rotation, scale, transform}
common_keyframes:     list (meist leer)
extra_material_refs:  list(7-9 UUIDs)
is_loop:              bool
keyframe_refs:        list (meist leer)
last_nonzero_volume:  float
material_id:          UUID
render_index:         int
reverse:              bool
source_timerange:     {start: us, duration: us}
speed:                float (1.0 = normal)
target_timerange:     {start: us, duration: us}
visible:              bool
volume:               float
```

Trivial — kann sofort gebaut werden.

---

## 2. `duplicate_clip` — Bereit

Deep-Copy eines Segments + zugehoeriger Materialien mit neuen UUIDs.

```
Input:  project_id (string), clip_id (string)
        start_ms (integer, optional — neue Timeline-Position, default: direkt nach Original)
        target_track_index (integer, optional — Ziel-Track, default: gleicher Track)
Output: new_clip_id (string)
```

### Implementierung

1. `find_segment` — Original-Segment und Track finden
2. Material per `material_id` in `draft["materials"]` suchen (alle Kategorien durchgehen)
3. Deep-Copy Segment: neue UUID fuer `id`
4. Deep-Copy Material: neue UUID fuer `id`, Segment bekommt neue `material_id`
5. `extra_material_refs` — hier wird es komplex:

### Das extra_material_refs Problem

Echte CapCut-Segmente haben 7-9 Eintraege in `extra_material_refs`, die auf Materials in verschiedenen Kategorien zeigen:

```
extra_material_refs eines typischen Video-Segments:
  -> materials.speeds             (type=speed)              — Geschwindigkeits-Einstellung
  -> materials.placeholder_infos  (type=placeholder_info)   — Platzhalter-Metadaten
  -> materials.canvases           (type=canvas_color)       — Hintergrund-Einstellung
  -> materials.material_animations (type=sticker_animation) — Animationen
  -> materials.sound_channel_mappings (type=none)           — Audio-Kanal-Mapping
  -> materials.material_colors    (type=)                   — Farbeinstellungen
  -> materials.loudnesses         (type=)                   — Lautstaerke-Normalisierung
  -> materials.vocal_separations  (type=vocal_separation)   — Vocal-Separation
  -> materials.effects            (type=mix_mode)           — Blend Mode (optional, 8. oder 9. Ref)
```

**Entscheidung fuer duplicate_clip:**
- **Option A (einfach):** Nur Segment + Haupt-Material kopieren, `extra_material_refs` leer lassen.
  CapCut ergaenzt fehlende Refs beim Oeffnen. Risiko: CapCut koennte das Segment ignorieren.
- **Option B (sicher):** Alle referenzierten Materials ebenfalls deep-copyen.
  Aufwaendiger, aber garantiert kompatibel.

**Empfehlung: Option B.** Algorithmus:
```
fuer jede ref_id in extra_material_refs:
    finde Material in allen materials-Kategorien
    deep-copy mit neuer UUID
    fuege Copy in gleiche Kategorie ein
    ersetze ref_id im neuen Segment durch neue UUID
```

### Material-Strukturen fuer Deep-Copy

**speeds:**
```json
{"curve_speed": null, "id": "UUID", "mode": 0, "speed": 1.0, "type": "speed"}
```

**placeholder_infos:**
```json
{"error_path": "", "error_text": "", "id": "UUID", "meta_type": "none",
 "res_path": "", "res_text": "", "type": "placeholder_info"}
```

**canvases:**
```json
{"album_image": "", "blur": 0.0, "color": "", "id": "UUID", "image": "",
 "image_id": "", "image_name": "", "source_platform": 0, "team_id": "",
 "type": "canvas_color"}
```

**material_animations:**
```json
{"animations": [], "id": "UUID", "multi_language_current": "none",
 "type": "sticker_animation"}
```

**sound_channel_mappings:**
```json
{"audio_channel_mapping": 0, "id": "UUID", "is_config_open": false, "type": "none"}
```

**material_colors:**
```json
{"gradient_angle": 90.0, "gradient_colors": [], "gradient_percents": [],
 "height": 0.0, "id": "UUID", "is_color_clip": false, "is_gradient": false,
 "solid_color": "", "width": 0.0}
```

**loudnesses:**
```json
{"enable": false, "file_id": "", "id": "UUID", "loudness_param": null,
 "target_loudness": 0.0, "time_range": null}
```

**vocal_separations:**
```json
{"choice": 0, "enter_from": "", "final_algorithm": "", "id": "UUID",
 "production_path": "", "removed_sounds": [], "time_range": null,
 "type": "vocal_separation"}
```

### Hilfs-Funktion noetig

```elixir
# Findet ein Material per ID in allen Kategorien
find_material(draft, material_id) :: {:ok, {category, material}} | {:error, msg}
```

Diese Funktion sollte in `TimelineHelper` leben, da auch `get_clip_info` sie nutzen kann.

---

## 3. `add_keyframe` — Braucht Reverse-Engineering

### Was wir wissen

- Segment hat `common_keyframes: []` (immer leer in unseren Projekten)
- Segment hat `keyframe_refs: []` (immer leer)
- Draft hat top-level `keyframes` Map mit Sub-Arrays (alle leer):
  ```
  keyframes.adjusts, keyframes.audios, keyframes.effects,
  keyframes.filters, keyframes.handwrites, keyframes.stickers,
  keyframes.texts, keyframes.videos
  ```
- Draft hat `keyframe_graph_list: []` (leer)

### Was wir NICHT wissen

Die genaue Struktur eines Keyframe-Eintrags. Aus dem User-Dokument und pyCapCut:

```
Vermutete Struktur (nicht verifiziert):
{
  "id": "UUID",
  "property_type": "KFTypePositionX" | "KFTypePositionY" | "KFTypeScaleX" | ...
  "keyframe_list": [
    {
      "curveType": "Linear" | "Bezier",
      "time_offset": 1000000,    // us relativ zum Segment-Start
      "values": [0.5]            // Zielwert
    }
  ]
}
```

### Reverse-Engineering Anleitung

**MUSS vor der Implementierung durchgefuehrt werden:**

1. CapCut oeffnen, bestehendes Projekt laden
2. Einen Video-Clip auswaehlen
3. Im Inspector: einen Keyframe fuer "Position X" setzen bei z.B. 2 Sekunden
4. Einen zweiten Keyframe fuer "Opacity" setzen bei 4 Sekunden
5. Projekt speichern
6. `draft_content.json` mit der Version vor dem Keyframe diffen:
   ```bash
   diff <(python -m json.tool before.json) <(python -m json.tool after.json)
   ```
7. Dokumentieren:
   - Wo landen die Keyframes? (`common_keyframes`? `keyframes.videos`? Beide?)
   - Wie sieht ein einzelner Keyframe-Eintrag aus?
   - Welche `property_type` Strings gibt es?
   - Werden `keyframe_refs` gesetzt?

### Geplantes Tool-Interface

```
Input:
  project_id:  string
  clip_id:     string
  property:    string   ("alpha" | "position_x" | "position_y" |
                          "scale_x" | "scale_y" | "rotation" | "volume")
  time_ms:     integer  (Position relativ zum Clip-Start)
  value:       float    (Zielwert)
  curve:       string   ("linear" | "bezier", default: "linear")
```

### Keyframe-Property Mapping (aus pyCapCut, nicht verifiziert)

```
alpha       -> KFTypePositionX ???  (unklar, muss geprueft werden)
position_x  -> clip.transform.x
position_y  -> clip.transform.y
scale_x     -> clip.scale.x
scale_y     -> clip.scale.y
rotation    -> clip.rotation
volume      -> segment.volume
```

---

## 4. `add_mask` — Braucht Reverse-Engineering

### Was wir wissen

- Materials-Kategorie heisst `common_mask` (nicht `masks`)
- In Projekt 0404: `common_mask: []` (leer — keine Masken verwendet)
- Segment hat `enable_video_mask: true` (Default fuer Video-Segmente)
- Segment hat `enable_mask_shadow: false` und `enable_mask_stroke: false`

### Was wir NICHT wissen

Die Struktur eines Masken-Materials und wie es referenziert wird.

Vermutung basierend auf pyCapCut:
```json
{
  "id": "UUID",
  "type": "mask",
  "mask_type": "rectangle",  // oder "circle", "mirror", "heart", "star"
  "width": 0.5,              // relativ zur Clip-Breite
  "height": 0.5,
  "center_x": 0.0,
  "center_y": 0.0,
  "feather": 0.1,            // Kanten-Weichzeichnung
  "round_corner": 0.0,       // Ecken-Rundung (nur Rechteck)
  "invert": false
}
```

### Reverse-Engineering Anleitung

1. CapCut oeffnen, Video-Clip auswaehlen
2. Maske hinzufuegen: Rechteck-Maske
3. Groesse und Position anpassen
4. Feather-Wert setzen
5. Speichern und JSON diffen
6. Dokumentieren:
   - Wie sieht ein `common_mask` Eintrag aus?
   - Wird die Maske via `extra_material_refs` referenziert?
   - Aendert sich `enable_video_mask`?
   - Gibt es separate Felder fuer Masken-Transform?

### Geplantes Tool-Interface

```
Input:
  project_id:  string
  clip_id:     string
  type:        string   ("rectangle" | "circle" | "mirror" | "heart" | "star")
  width:       float    (0.0-1.0, relativ zur Clip-Breite)
  height:      float    (0.0-1.0)
  x:           float    (Masken-Center-Offset, default: 0.0)
  y:           float    (Masken-Center-Offset, default: 0.0)
  feather:     float    (Kanten-Weichzeichnung, 0.0-1.0, default: 0.0)
  invert:      boolean  (Maske invertieren, default: false)
```

---

## Bestehende Infrastruktur die wiederverwendet wird

### TimelineHelper (`lib/capcut_mcp/tools/timeline_helper.ex`)

```elixir
generate_uuid()                           # UUID v4 generieren
find_segment(draft, segment_id)           # Segment in allen Tracks finden
update_segment(draft, segment_id, fn)     # Segment in-place updaten
insert_segment(tracks, segment, type, idx) # Segment in Track einfuegen
add_material(draft, category, material)   # Material hinzufuegen
validate_timing(start_ms, duration_ms)    # Timing validieren
validate_track_index(tracks, idx)         # Track-Index validieren
```

### Neue Helper die fuer Prio 2 gebaut werden sollten

```elixir
# In TimelineHelper:
find_material(draft, material_id) :: {:ok, {category_key, material}} | {:error, msg}
deep_copy_material(material) :: map()  # Kopiert Material mit neuer UUID
```

### Tool-Pattern (aus Prio 1)

```elixir
defmodule CapcutMcp.Tools.NewTool do
  @behaviour CapcutMcp.Tool

  def definition, do: %{"name" => ..., "description" => ..., "inputSchema" => ...}

  def execute(%{"project_id" => id, ...} = args) do
    with {:ok, draft} <- ProjectStore.get_project(id),
         {:ok, updated_draft} <- apply_changes(draft, args),
         :ok <- ProjectStore.update_project(id, updated_draft) do
      {:ok, "Success message"}
    else
      {:error, :not_found} -> {:error, "Project not found: #{id}"}
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
end
```

Registrierung: Module in `lib/capcut_mcp/mcp/dispatcher.ex` alias + `@tools` Liste.

---

## Empfohlene Reihenfolge

1. **`get_clip_info`** — trivial, sofort machbar, nuetzlich fuer Debugging
2. **`duplicate_clip`** — mittlerer Aufwand, aber keine Unbekannten
3. **Reverse-Engineering Session** — Keyframes + Masken in CapCut setzen, JSON diffen
4. **`add_keyframe`** — nach dem Reverse-Engineering
5. **`add_mask`** — nach dem Reverse-Engineering

---

## Referenz-Repos

- **pyCapCut** (Python): https://github.com/GuanYixuan/pyCapCut
  -> `ClipSettings`, `KeyframeProperty`, `MaskType` dokumentiert
  -> Gute Quelle fuer Property-Namen und Strukturen
- **capcut-mate** (FastAPI): https://github.com/Hommy-master/capcut-mate
  -> REST-API mit aehnlichen Tools
- **CapCutAPI** (MCP-ready): https://github.com/ashreo/CapCutAPI
  -> Hat `add_video_keyframe` bereits implementiert

---

## Echte CapCut JSON Referenz

### Materials-Kategorien (54 Keys in echtem Projekt)

Fett = von uns genutzt, *kursiv* = relevant fuer Prio 2:

- **audios**, **videos**, **texts**, **effects**, **canvases**
- *common_mask*, *material_animations*
- **speeds**, **sound_channel_mappings**, **material_colors**
- **loudnesses**, **vocal_separations**, **placeholder_infos**
- audio_balances, audio_effects, audio_fades, audio_pannings
- audio_pitch_shifts, audio_track_indexes, beats, chromas
- color_curves, digital_human_model_dressing, digital_humans
- drafts, flowers, green_screens, handwrites, hsl, hsl_curves
- images, log_color_wheels, manual_beautys, manual_deformations
- multi_language_refs, placeholders, plugin_effects
- primary_color_wheels, realtime_denoises, shapes, smart_crops
- smart_relights, stickers, tail_leaders, text_templates
- time_marks, transitions, video_effects, video_radius
- video_shadows, video_strokes, video_trackings
- vocal_beautifys, ai_translates, filters
