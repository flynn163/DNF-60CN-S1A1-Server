#pragma once

#include <array>
#include <cstdint>

#include "output_paths.h"

namespace dfl::dnf_patches
{
	inline constexpr bool DisableDebuggerDetection = true;
	inline constexpr bool AllowMultipleClientInstances = true;
	inline constexpr bool DisableStartupMinimize = true;
	inline constexpr bool SinglePermanentAvatarPeriodOption = true;
	inline constexpr bool EnableCustomStackableUseMode1 = true;
	inline constexpr bool RemoveCustomPopupAnnouncementTitle = true;
	inline constexpr bool UseExternalDnfStringTable = true;
	inline constexpr bool FixMailboxArchiveRefresh = true;
	inline constexpr bool RepairAllWornEquipmentOnly = true;
	inline constexpr bool BypassCeraPurchaseRestrictions = true;
	// Skip the client's rotate/xor calls at the confirmed log writers so the
	// DNF.trc and NeopleEngine streams remain plain text without changing
	// unrelated string helpers.
	inline constexpr bool ForcePlainTextLogs = true;

    namespace detail
    {
        struct RepairAllScopePatch
        {
            std::uintptr_t Address;
            std::uintptr_t ResumeAddress;
            std::array<unsigned char, 6> Expected;
            std::array<unsigned char, 6> Replacement;
        };

        inline constexpr std::array<RepairAllScopePatch, 2> RepairAllScopePatches{{
            {
                // sub_7CDC10: return the worn-only price/count before scanning
                // the main bag. Both affordability and the confirm dialog use it.
                0x007CDC83,
                0x007CDEA9,
                {0x8B, 0x35, 0xEC, 0xDC, 0xB5, 0x00},
                {0xE9, 0x21, 0x02, 0x00, 0x00, 0x90}
            },
            {
                // REPLY25's 0xFFFF branch: keep the worn loop, skip the main-bag
                // durability fill, then retain window cleanup and ITEM_REPAIR.
                0x00411C79,
                0x00411D6B,
                {0x8B, 0x0D, 0xEC, 0xDC, 0xB5, 0x00},
                {0xE9, 0xED, 0x00, 0x00, 0x00, 0x90}
            }
        }};
    }

	enum class CeraPurchaseGate
	{
		LegacySaleWindow,
		PerCharacterLimit,
		CharacterLevel,
		ClientInventoryCapacity,
		JobCompatibility,
		CurrencyBalance,
		RequiredOption,
		GiftEligibility,
	};

	constexpr bool ShouldBypassCeraPurchaseGate(
		CeraPurchaseGate gate) noexcept
	{
		if (!BypassCeraPurchaseRestrictions)
		{
			return false;
		}

		switch (gate)
		{
		case CeraPurchaseGate::LegacySaleWindow:
		case CeraPurchaseGate::PerCharacterLimit:
		case CeraPurchaseGate::CharacterLevel:
			return true;

		case CeraPurchaseGate::ClientInventoryCapacity:
		case CeraPurchaseGate::JobCompatibility:
		case CeraPurchaseGate::CurrencyBalance:
		case CeraPurchaseGate::RequiredOption:
		case CeraPurchaseGate::GiftEligibility:
			return false;
		}

		return false;
	}

	// Add [etc] stackable item IDs here. Listed items use the client's mode-1
	// path and therefore send command 47. Rebuild IJL15 after every change.
	inline constexpr std::uint32_t EtcStackableUseMode1ItemIds[] = {
		7518,
		7519,
		1121,
		1122,
		1123,
	};

	constexpr bool IsEtcStackableUseMode1ItemId(
		std::uint32_t itemId) noexcept
	{
		for (const std::uint32_t configuredItemId
			: EtcStackableUseMode1ItemIds)
		{
			if (configuredItemId == itemId)
			{
				return true;
			}
		}
		return false;
	}

	inline constexpr std::uint32_t CeraBoosterStackableType = 13;

	constexpr bool ShouldUseStackableMode1(
		std::uint32_t itemId,
		std::uint32_t stackableType) noexcept
	{
		return stackableType == CeraBoosterStackableType
			|| stackableType == 10
				&& IsEtcStackableUseMode1ItemId(itemId);
	}

    // The FPS/memory overlay and mouse-wheel hook are runtime options in the
    // Config.ini file beside DNF.exe. Their defaults are enabled there.
	// Keep Type16Brown text but suppress the client's CHAT_MESSAGE notification
	// sound. Type4Brown and other message types retain their normal behavior.
	inline constexpr bool DisableType16ChatMessageSound = true;

	bool IsTargetProcess() noexcept;
	bool Apply() noexcept;
}
