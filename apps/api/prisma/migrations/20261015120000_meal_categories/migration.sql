-- AlterTable
ALTER TABLE `DiaryEntry` ADD COLUMN `meal` ENUM('breakfast', 'lunch', 'dinner', 'snacks') NOT NULL DEFAULT 'snacks';
