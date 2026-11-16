-- CreateTable
CREATE TABLE `WeightGoal` (
    `userId` VARCHAR(191) NOT NULL,
    `targetKg` DECIMAL(6, 2) NOT NULL,
    `startKg` DECIMAL(6, 2) NOT NULL,
    `setAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    PRIMARY KEY (`userId`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- AddForeignKey
ALTER TABLE `WeightGoal` ADD CONSTRAINT `WeightGoal_userId_fkey` FOREIGN KEY (`userId`) REFERENCES `User`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;
