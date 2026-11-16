-- AlterTable: foods and diary entries can be measured per unit (egg, slice) as well as per 100 g / 100 ml.
ALTER TABLE `Food` MODIFY `basis` ENUM('solid', 'liquid', 'unit') NOT NULL;
ALTER TABLE `DiaryEntry` MODIFY `basis` ENUM('solid', 'liquid', 'unit') NOT NULL;
