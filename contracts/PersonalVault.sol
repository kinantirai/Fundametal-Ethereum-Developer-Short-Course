// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title PersonalVault
/// @author (Isi nama/alias Anda di sini)
/// @notice Time-Locked Personal Vault untuk menyimpan ETH secara aman hingga waktu tertentu.
/// @dev Mengimplementasikan pola Checks-Effects-Interactions (CEI), custom errors untuk
///      efisiensi gas, dan visibility `external` pada fungsi yang tidak dipanggil secara
///      internal untuk optimasi gas tambahan.
contract PersonalVault {
    /// @notice Alamat pemilik vault yang berhak menarik dan memperpanjang kunci.
    address public owner;

    /// @notice Timestamp (unix) saat dana boleh mulai ditarik.
    uint256 public unlockTime;

    /// @notice Dipancarkan setiap kali ETH masuk ke vault (deposit, receive, atau saat deploy).
    /// @param sender Alamat pengirim ETH.
    /// @param amount Jumlah ETH yang disetor (dalam wei).
    event Deposit(address indexed sender, uint256 amount);

    /// @notice Dipancarkan saat owner berhasil menarik seluruh saldo vault.git 
    /// @param amount Jumlah ETH yang ditarik (dalam wei).
    /// @param timestamp Waktu penarikan terjadi.
    event Withdrawal(uint256 amount, uint256 timestamp);

    /// @notice Dipancarkan saat owner memperpanjang waktu unlock.
    /// @param newUnlockTime Timestamp unlock yang baru.
    event LockExtended(uint256 newUnlockTime);

    /// @notice Dilempar saat penarikan dicoba sebelum unlockTime tercapai.
    error FundsLocked();

    /// @notice Dilempar saat pemanggil bukan owner vault.
    error NotOwner();

    /// @notice Dilempar saat unlockTime baru tidak valid (harus lebih besar dari waktu sekarang/lama).
    error InvalidUnlockTime();

    /// @notice Dilempar saat mencoba menarik dana namun saldo vault kosong.
    error BalanceZero();

    /// @notice Dilempar saat transfer ETH native (low-level call) gagal.
    error TransferFailed();

    /// @notice Membatasi akses fungsi hanya untuk owner vault.
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @notice Membuat vault baru dan menetapkan waktu unlock awal.
    /// @dev Bisa menerima ETH langsung saat deployment (constructor payable).
    ///      Jika ada ETH terkirim saat deploy, event Deposit dipancarkan agar
    ///      tidak ada setoran awal yang tidak tercatat off-chain.
    /// @param _unlockTime Timestamp unix kapan dana boleh ditarik. Harus lebih besar dari waktu sekarang.
    constructor(uint256 _unlockTime) payable {
        if (_unlockTime <= block.timestamp) revert InvalidUnlockTime();
        owner = msg.sender;
        unlockTime = _unlockTime;

        if (msg.value > 0) {
            emit Deposit(msg.sender, msg.value);
        }
    }

    /// @notice Menyetor ETH ke dalam vault.
    /// @dev Visibility `external` karena tidak dipanggil secara internal oleh kontrak,
    ///      sedikit lebih hemat gas dibanding `public`.
    function deposit() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    /// @notice Menarik seluruh saldo vault ke owner, hanya bisa dilakukan setelah unlockTime.
    /// @dev Mengikuti pola Checks-Effects-Interactions (CEI):
    ///      1. Checks  : memastikan waktu sudah unlock dan saldo tidak kosong.
    ///      2. Effects : memancarkan event sebelum interaksi eksternal.
    ///      3. Interactions : mengirim ETH menggunakan `call` (bukan `transfer`/`send`)
    ///         untuk menghindari masalah gas stipend pada penerima kontrak.
    ///      Visibility `external` karena tidak dipanggil secara internal.
    function withdraw() external onlyOwner {
        // ---- 1. CHECKS ----
        if (block.timestamp < unlockTime) revert FundsLocked();

        uint256 balance = address(this).balance;
        if (balance == 0) revert BalanceZero();

        // ---- 2. EFFECTS ----
        emit Withdrawal(balance, block.timestamp);

        // ---- 3. INTERACTIONS ----
        (bool success, ) = payable(owner).call{value: balance}("");
        if (!success) revert TransferFailed();
    }

    /// @notice Memperpanjang waktu unlock vault ke waktu yang lebih baru.
    /// @dev Visibility `external` karena tidak dipanggil secara internal.
    /// @param newTime Timestamp unlock baru, harus lebih besar dari unlockTime saat ini.
    function extendLock(uint256 newTime) external onlyOwner {
        if (newTime <= unlockTime) revert InvalidUnlockTime();
        unlockTime = newTime;
        emit LockExtended(newTime);
    }

    /// @notice Menerima transfer ETH langsung (tanpa memanggil fungsi apapun) ke alamat kontrak.
    /// @dev Memastikan setoran langsung via wallet tetap tercatat lewat event Deposit,
    ///      sehingga tidak ada dana masuk yang tidak terlacak off-chain.
    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }
}