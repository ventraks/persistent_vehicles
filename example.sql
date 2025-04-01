CREATE TABLE IF NOT EXISTS `player_vehicles` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `owner_identifier` VARCHAR(100) NOT NULL,          -- Player's license, steam hex, etc.
  `plate` VARCHAR(12) NOT NULL,                    -- Vehicle license plate
  `model` BIGINT NOT NULL,                         -- Vehicle model hash (use BIGINT for safety)
  `pos_x` FLOAT NOT NULL,
  `pos_y` FLOAT NOT NULL,
  `pos_z` FLOAT NOT NULL,
  `heading` FLOAT NOT NULL,
  `vehicle_properties` LONGTEXT NOT NULL,          -- Store JSON encoded properties (mods, colors etc.)
  `fuel_level` FLOAT NOT NULL,
  `health_engine` FLOAT NOT NULL,
  `health_body` FLOAT NOT NULL,
  `health_tyres` TEXT,                             -- Store JSON encoded tyre status
  `health_windows` TEXT,                           -- Store JSON encoded window status
  `health_doors` TEXT,                             -- Store JSON encoded door status
  `locked` BOOLEAN NOT NULL DEFAULT FALSE,
  `last_update` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  UNIQUE KEY `owner_plate_idx` (`owner_identifier`, `plate`), -- Ensure one entry per player per plate
  INDEX `owner_idx` (`owner_identifier`)           -- Index for faster lookup by owner
);
