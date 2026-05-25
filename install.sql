-- sc_timeclock SQL
-- Run this once on your database

CREATE TABLE IF NOT EXISTS `timeclock_sessions` (
    `id`            INT(11)         NOT NULL AUTO_INCREMENT,
    `citizenid`     VARCHAR(50)     NOT NULL,
    `job`           VARCHAR(50)     NOT NULL,
    `clock_in`      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `clock_out`     DATETIME        NULL DEFAULT NULL,
    `duration_secs` INT(11)         NULL DEFAULT NULL COMMENT 'Populated on clock-out',
    `forced_by`     VARCHAR(50)     NULL DEFAULT NULL COMMENT 'citizenid of manager who forced action',
    `created_at`    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_citizenid_job` (`citizenid`, `job`),
    INDEX `idx_clock_out`     (`clock_out`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
