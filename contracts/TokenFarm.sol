// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./DAppToken.sol";
import "./LPToken.sol";

/**
 * @title Proportional Token Farm
 * @notice Una granja de staking donde las recompensas se distribuyen proporcionalmente al total stakeado.
 */
contract TokenFarm {
    //
    // Variables de estado
    //
    string public name = "Proportional Token Farm";
    address public owner;
    DAppToken public dappToken;
    LPToken public lpToken;

    uint256 public constant REWARD_PER_BLOCK = 1e18; // Recompensa por bloque (total para todos los usuarios)
    uint256 public totalStakingBalance; // Total de tokens en staking

    address[] public stakers;

    // Struct para manejar información del usuario
    struct UserInfo {
        uint256 stakingBalance;
        uint256 checkpoint;
        uint256 pendingRewards;
        bool hasStaked;
        bool isStaking;
    }

    mapping(address => UserInfo) public users;

    // Eventos
    // Agregar eventos para Deposit, Withdraw, RewardsClaimed y RewardsDistributed.
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardsDistributed();

    // Constructor
    constructor(DAppToken _dappToken, LPToken _lpToken) {
        // Configurar las instancias de los contratos de DappToken y LPToken.
        dappToken = _dappToken;
        lpToken = _lpToken;
        // Configurar al owner del contrato como el creador de este contrato.
        owner = msg.sender;
    }

    // Modificadores
    modifier onlyStaker() {
        require(users[msg.sender].isStaking, "Caller is not staking");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    /**
     * @notice Deposita tokens LP para staking.
     * @param _amount Cantidad de tokens LP a depositar.
     */
    function deposit(uint256 _amount) external {
        // Verificar que _amount sea mayor a 0.
        // Transferir tokens LP del usuario a este contrato.
        require(_amount > 0, "Amount must be greater than 0");

        UserInfo storage user = users[msg.sender];

        lpToken.transferFrom(msg.sender, address(this), _amount);
        // Actualizar el balance de staking del usuario en stakingBalance.
        // Incrementar totalStakingBalance con _amount.
        // Si el usuario nunca ha hecho staking antes, agregarlo al array stakers y marcar hasStaked como true.
        // Actualizar isStaking del usuario a true.
        user.stakingBalance += _amount;
        totalStakingBalance += _amount;

        if (!user.hasStaked) {
            stakers.push(msg.sender);
            user.hasStaked = true;
        }
        user.isStaking = true;
        // Si checkpoints del usuario está vacío, inicializarlo con el número de bloque actual.
        // Llamar a distributeRewards para calcular y actualizar las recompensas pendientes.
        if (user.checkpoint == 0) {
            user.checkpoint = block.number;
        }
        distributeRewards(msg.sender);
        // Emitir un evento de depósito.
        emit Deposit(msg.sender, _amount);
    }

    /**
     * @notice Retira todos los tokens LP en staking.
     */
    function withdraw() external onlyStaker {
        // Verificar que el usuario está haciendo staking (isStaking == true).
        // Obtener el balance de staking del usuario.
        // Verificar que el balance de staking sea mayor a 0.
        // Llamar a distributeRewards para calcular y actualizar las recompensas pendientes antes de restablecer el balance.
        UserInfo storage user = users[msg.sender];
        uint256 balance = user.stakingBalance;
        require(balance > 0, "Staking balance must be greater than 0");

        distributeRewards(msg.sender);
        // Restablecer stakingBalance del usuario a 0.
        // Reducir totalStakingBalance en el balance que se está retirando.
        // Actualizar isStaking del usuario a false.
        // Transferir los tokens LP de vuelta al usuario.
        user.stakingBalance = 0;
        totalStakingBalance -= balance;
        user.isStaking = false;

        lpToken.transfer(msg.sender, balance);
        // Emitir un evento de retiro.
        emit Withdraw(msg.sender, balance);
    }

    /**
     * @notice Reclama recompensas pendientes.
     */
    function claimRewards() external onlyStaker {
         UserInfo storage user = users[msg.sender];
        // Obtener el monto de recompensas pendientes del usuario desde pendingRewards.
        distributeRewards(msg.sender);

        uint256 pendingAmount = user.pendingRewards;
        // Verificar que el monto de recompensas pendientes sea mayor a 0.
        // Restablecer las recompensas pendientes del usuario a 0.
        // Llamar a la función de acuñación (mint) en el contrato DappToken para transferir las recompensas al usuario.
        require(pendingAmount > 0, "No rewards to claim");

        user.pendingRewards = 0;

        dappToken.mint(msg.sender, pendingAmount);
        // Emitir un evento de reclamo de recompensas.
        emit RewardsClaimed(msg.sender, pendingAmount);
    }

    /**
     * @notice Distribuye recompensas a todos los usuarios en staking.
     */
    function distributeRewardsAll() external onlyOwner{
        // Verificar que la llamada sea realizada por el owner.
        // Iterar sobre todos los usuarios en staking almacenados en el array stakers.
        // Para cada usuario, si están haciendo staking (isStaking == true), llamar a distributeRewards.
        // Emitir un evento indicando que las recompensas han sido distribuidas.
       
        for (uint256 i = 0; i < stakers.length; i++) {
            address staker = stakers[i];
            if (users[staker].isStaking) {
                distributeRewards(staker);
            }
        }

        emit RewardsDistributed();
    }

    /**
     * @notice Calcula y distribuye las recompensas proporcionalmente al staking total.
     * @dev La función toma en cuenta el porcentaje de tokens que cada usuario tiene en staking con respecto
     *      al total de tokens en staking (`totalStakingBalance`).
     *
     * Funcionamiento:
     * 1. Se calcula la cantidad de bloques transcurridos desde el último checkpoint del usuario.
     * 2. Se calcula la participación proporcional del usuario:
     *    share = stakingBalance[beneficiary] / totalStakingBalance
     * 3. Las recompensas para el usuario se determinan multiplicando su participación proporcional
     *    por las recompensas por bloque (`REWARD_PER_BLOCK`) y los bloques transcurridos:
     *    reward = REWARD_PER_BLOCK * blocksPassed * share
     * 4. Se acumulan las recompensas calculadas en `pendingRewards[beneficiary]`.
     * 5. Se actualiza el checkpoint del usuario al bloque actual.
     *
     * Ejemplo Práctico:
     * - Supongamos que:
     *    Usuario A ha stakeado 100 tokens.
     *    Usuario B ha stakeado 300 tokens.
     *    Total de staking (`totalStakingBalance`) = 400 tokens.
     *    `REWARD_PER_BLOCK` = 1e18 (1 token total por bloque).
     *    Han transcurrido 10 bloques desde el último checkpoint.
     *
     * Cálculo:
     * - Participación de Usuario A:
     *   shareA = 100 / 400 = 0.25 (25%)
     *   rewardA = 1e18 * 10 * 0.25 = 2.5e18 (2.5 tokens).
     *
     * - Participación de Usuario B:
     *   shareB = 300 / 400 = 0.75 (75%)
     *   rewardB = 1e18 * 10 * 0.75 = 7.5e18 (7.5 tokens).
     *
     * Resultado:
     * - Usuario A acumula 2.5e18 en `pendingRewards`.
     * - Usuario B acumula 7.5e18 en `pendingRewards`.
     *
     * Nota:
     * Este sistema asegura que las recompensas se distribuyan proporcionalmente y de manera justa
     * entre todos los usuarios en función de su contribución al staking total.
     */
    function distributeRewards(address beneficiary) private {
        UserInfo storage user = users[beneficiary];
        // Obtener el último checkpoint del usuario desde checkpoints.
        // Verificar que el número de bloque actual sea mayor al checkpoint y que totalStakingBalance sea mayor a 0.
        // Calcular la cantidad de bloques transcurridos desde el último checkpoint.
        // Calcular la proporción del staking del usuario en relación al total staking (stakingBalance[beneficiary] / totalStakingBalance).
        // Calcular las recompensas del usuario multiplicando la proporción por REWARD_PER_BLOCK y los bloques transcurridos.
        // Actualizar las recompensas pendientes del usuario en pendingRewards.
        // Actualizar el checkpoint del usuario al bloque actual.
        uint256 lastCheckpoint = user.checkpoint;
        require(block.number > lastCheckpoint, "No new blocks passed");
        require(totalStakingBalance > 0, "No staking balance");

        uint256 blocksPassed = block.number - lastCheckpoint;
        uint256 userShare = (user.stakingBalance * 1e18) / totalStakingBalance;
        uint256 reward = (REWARD_PER_BLOCK * blocksPassed * userShare) / 1e18;

        user.pendingRewards += reward;
        user.checkpoint = block.number;
    }
    }
