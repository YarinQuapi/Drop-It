-- CreateTable
CREATE TABLE `RolePermission` (
    `role` ENUM('user', 'admin') NOT NULL,
    `operation` VARCHAR(191) NOT NULL,
    `allowed` BOOLEAN NOT NULL DEFAULT true,
    `updatedAt` DATETIME(3) NOT NULL,

    PRIMARY KEY (`role`, `operation`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
