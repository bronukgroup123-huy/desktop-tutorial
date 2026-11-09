-- 002_triggers.sql
CREATE OR REPLACE FUNCTION trg_set_updated_at() RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER species_updated BEFORE UPDATE ON species
  FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();

CREATE OR REPLACE FUNCTION trg_update_has_photos() RETURNS TRIGGER AS $$
BEGIN
  UPDATE species SET has_photos = EXISTS (
    SELECT 1 FROM species_photos
    WHERE species_id = COALESCE(NEW.species_id, OLD.species_id)
  ) WHERE id = COALESCE(NEW.species_id, OLD.species_id);
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER photos_has_photos AFTER INSERT OR DELETE ON species_photos
  FOR EACH ROW EXECUTE FUNCTION trg_update_has_photos();

CREATE OR REPLACE FUNCTION trg_twins_set_clickable() RETURNS TRIGGER AS $$
BEGIN
  NEW.is_clickable := NEW.severity = 'deadly_poisonous'
    AND EXISTS (SELECT 1 FROM species WHERE id = NEW.twin_id AND has_photos);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER twins_clickable BEFORE INSERT OR UPDATE ON species_twins
  FOR EACH ROW EXECUTE FUNCTION trg_twins_set_clickable();

-- Червонокнижні не мають прив'язки до областей
CREATE OR REPLACE FUNCTION trg_block_region_for_red_listed() RETURNS TRIGGER AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM species WHERE id = NEW.species_id
      AND (is_red_listed OR rarity_label_uk IS NOT NULL)
  ) THEN
    RAISE EXCEPTION 'red_listed_no_region'
      USING HINT = 'Червонокнижні не мають прив''язки до областей';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER regions_no_red_listed
  BEFORE INSERT OR UPDATE ON species_regions
  FOR EACH ROW EXECUTE FUNCTION trg_block_region_for_red_listed();

-- Рушій не приймає ЧК
CREATE OR REPLACE FUNCTION trg_expert_rules_no_red() RETURNS TRIGGER AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM species WHERE id = NEW.species_id
      AND (is_red_listed OR rarity_label_uk IS NOT NULL)
  ) THEN
    RAISE EXCEPTION 'Червонокнижні не можуть мати правил прогнозу';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER expert_rules_red BEFORE INSERT OR UPDATE ON expert_rules
  FOR EACH ROW EXECUTE FUNCTION trg_expert_rules_no_red();

-- Picks не приймають ЧК
CREATE OR REPLACE FUNCTION trg_picks_no_red() RETURNS TRIGGER AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM species WHERE id = NEW.species_id
      AND (is_red_listed OR rarity_label_uk IS NOT NULL)
  ) THEN
    RAISE EXCEPTION 'restricted_species';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER picks_red BEFORE INSERT ON mushroom_picks
  FOR EACH ROW EXECUTE FUNCTION trg_picks_no_red();
