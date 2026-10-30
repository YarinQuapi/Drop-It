-- AlterTable
ALTER TABLE `DailyGoal` ADD COLUMN `healthAdjusted` BOOLEAN NOT NULL DEFAULT false;

-- AlterTable
ALTER TABLE `WeightEntry` ADD COLUMN `source` ENUM('manual', 'health') NOT NULL DEFAULT 'manual',
    ADD COLUMN `externalId` VARCHAR(64) NULL;

-- CreateTable
CREATE TABLE `HealthSettings` (
    `userId` VARCHAR(191) NOT NULL,
    `connected` BOOLEAN NOT NULL DEFAULT false,
    `connectedOn` DATE NULL,
    `lastSyncedAt` DATETIME(3) NULL,
    `exerciseGoalMinutes` INTEGER NOT NULL DEFAULT 30,
    `stepGoal` INTEGER NOT NULL DEFAULT 10000,

    PRIMARY KEY (`userId`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `HealthDay` (
    `id` VARCHAR(191) NOT NULL,
    `userId` VARCHAR(191) NOT NULL,
    `day` DATE NOT NULL,
    `steps` INTEGER NOT NULL DEFAULT 0,
    `exerciseMinutes` INTEGER NOT NULL DEFAULT 0,
    `activeKcal` INTEGER NOT NULL DEFAULT 0,
    `syncedAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    UNIQUE INDEX `HealthDay_userId_day_key`(`userId`, `day`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateIndex
CREATE UNIQUE INDEX `WeightEntry_userId_externalId_key` ON `WeightEntry`(`userId`, `externalId`);

-- AddForeignKey
ALTER TABLE `HealthSettings` ADD CONSTRAINT `HealthSettings_userId_fkey` FOREIGN KEY (`userId`) REFERENCES `User`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `HealthDay` ADD CONSTRAINT `HealthDay_userId_fkey` FOREIGN KEY (`userId`) REFERENCES `User`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;
