-- AlterTable
ALTER TABLE `DiaryEntry` MODIFY `meal` ENUM('breakfast', 'lunch', 'dinner', 'snacks', 'drinks') NOT NULL DEFAULT 'snacks';
