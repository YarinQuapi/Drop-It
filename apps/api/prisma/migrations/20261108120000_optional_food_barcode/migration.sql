-- AlterTable: loose foods (fruit, home cooking) have no barcode.
ALTER TABLE `Food` MODIFY `barcode` VARCHAR(191) NULL;
