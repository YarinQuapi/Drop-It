-- AlterTable
ALTER TABLE `User` MODIFY `passwordHash` VARCHAR(191) NULL,
    ADD COLUMN `appleSub` VARCHAR(191) NULL;

-- CreateIndex
CREATE UNIQUE INDEX `User_appleSub_key` ON `User`(`appleSub`);
