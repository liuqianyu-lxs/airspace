package main

import (
	"encoding/json"
	"fmt"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// SmartContract provides functions for managing airspace
type SmartContract struct {
	contractapi.Contract
}

// AirspaceSlot represents a 4D airspace allocation
type AirspaceSlot struct {
	ID       string  `json:"id"`       // 唯一标识符
	X        float64 `json:"x"`        // X坐标
	Y        float64 `json:"y"`        // Y坐标
	Z        float64 `json:"z"`        // Z坐标
	TimeSlot int64   `json:"timeSlot"` // 时间槽
	Airline  string  `json:"airline"`  // 占用航司
	Status   string  `json:"status"`   // 状态（free/occupied/reserved）
}

// InitLedger 初始化账本
func (s *SmartContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	return nil
}

// RequestAirspace 申请空域
func (s *SmartContract) RequestAirspace(ctx contractapi.TransactionContextInterface, id string, x float64, y float64, z float64, timeSlot int64) error {
	// 检查调用者身份
	airline, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return fmt.Errorf("failed to get client identity: %v", err)
	}

	// 检查空域是否已被占用
	exists, err := s.AirspaceExists(ctx, x, y, z, timeSlot)
	if err != nil {
		return err
	}
	if exists {
		return fmt.Errorf("airspace already occupied")
	}

	// 创建新的空域分配
	airspace := AirspaceSlot{
		ID:       id,
		X:        x,
		Y:        y,
		Z:        z,
		TimeSlot: timeSlot,
		Airline:  airline,
		Status:   "occupied",
	}

	airspaceJSON, err := json.Marshal(airspace)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(id, airspaceJSON)
}

// AirspaceExists 检查空域是否被占用
func (s *SmartContract) AirspaceExists(ctx contractapi.TransactionContextInterface, x float64, y float64, z float64, timeSlot int64) (bool, error) {
	// 实现空域冲突检测逻辑
	// 可以定义一个容差范围
	tolerance := 0.1

	resultsIterator, err := ctx.GetStub().GetStateByRange("", "")
	if err != nil {
		return false, err
	}
	defer resultsIterator.Close()

	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return false, err
		}

		var existingSlot AirspaceSlot
		err = json.Unmarshal(queryResponse.Value, &existingSlot)
		if err != nil {
			return false, err
		}

		// 检查空间和时间是否重叠
		if abs(existingSlot.X-x) < tolerance &&
			abs(existingSlot.Y-y) < tolerance &&
			abs(existingSlot.Z-z) < tolerance &&
			existingSlot.TimeSlot == timeSlot {
			return true, nil
		}
	}

	return false, nil
}

// QueryAirspace 查询特定空域状态
func (s *SmartContract) QueryAirspace(ctx contractapi.TransactionContextInterface, id string) (*AirspaceSlot, error) {
	airspaceJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return nil, fmt.Errorf("failed to read from world state: %v", err)
	}
	if airspaceJSON == nil {
		return nil, fmt.Errorf("the airspace %s does not exist", id)
	}

	var airspace AirspaceSlot
	err = json.Unmarshal(airspaceJSON, &airspace)
	if err != nil {
		return nil, err
	}

	return &airspace, nil
}

// ReleaseAirspace 释放空域
func (s *SmartContract) ReleaseAirspace(ctx contractapi.TransactionContextInterface, id string) error {
	airspace, err := s.QueryAirspace(ctx, id)
	if err != nil {
		return err
	}

	// 检查调用者身份
	airline, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return fmt.Errorf("failed to get client identity: %v", err)
	}

	// 验证释放权限
	if airspace.Airline != airline {
		return fmt.Errorf("airspace can only be released by the occupying airline")
	}

	airspace.Status = "free"
	airspaceJSON, err := json.Marshal(airspace)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(id, airspaceJSON)
}

// 辅助函数：计算绝对值
func abs(x float64) float64 {
	if x < 0 {
		return -x
	}
	return x
}

func main() {
	chaincode, err := contractapi.NewChaincode(&SmartContract{})
	if err != nil {
		fmt.Printf("Error creating airspace chaincode: %s", err.Error())
		return
	}

	if err := chaincode.Start(); err != nil {
		fmt.Printf("Error starting airspace chaincode: %s", err.Error())
	}
}
