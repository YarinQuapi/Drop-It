-- CreateTable
CREATE TABLE `ScanReport` (
    `id` VARCHAR(191) NOT NULL,
    `userId` VARCHAR(191) NOT NULL,
    `photo` LONGBLOB NOT NULL,
    `rawText` TEXT NOT NULL,
    `parsed` JSON NOT NULL,
    `note` VARCHAR(500) NOT NULL DEFAULT '',
    `language` VARCHAR(8) NOT NULL,
    `resolvedAt` DATETIME(3) NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    INDEX `ScanReport_resolvedAt_createdAt_idx`(`resolvedAt`, `createdAt`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- AddForeignKey
ALTER TABLE `ScanReport` ADD CONSTRAINT `ScanReport_userId_fkey` FOREIGN KEY (`userId`) REFERENCES `User`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;
