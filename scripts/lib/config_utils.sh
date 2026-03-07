#!/bin/bash

trim_value() {
	local value="$1"
	echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

apply_tun_config() {
	local config_path="$1"
	local enable="${CLASH_TUN_ENABLE:-false}"
	if [ "$enable" != "true" ]; then
		return 0
	fi

	local stack="${CLASH_TUN_STACK:-system}"
	local auto_route="${CLASH_TUN_AUTO_ROUTE:-true}"
	local auto_redirect="${CLASH_TUN_AUTO_REDIRECT:-false}"
	local strict_route="${CLASH_TUN_STRICT_ROUTE:-false}"
	local device="${CLASH_TUN_DEVICE:-}"
	local mtu="${CLASH_TUN_MTU:-}"
	local dns_hijack="${CLASH_TUN_DNS_HIJACK:-}"

	{
		echo ""
		echo "tun:"
		echo "  enable: true"
		echo "  stack: ${stack}"
		echo "  auto-route: ${auto_route}"
		echo "  auto-redirect: ${auto_redirect}"
		echo "  strict-route: ${strict_route}"
		if [ -n "$device" ]; then
			echo "  device: ${device}"
		fi
		if [ -n "$mtu" ]; then
			echo "  mtu: ${mtu}"
		fi
		if [ -n "$dns_hijack" ]; then
			echo "  dns-hijack:"
			IFS=',' read -r -a hijacks <<< "$dns_hijack"
			for item in "${hijacks[@]}"; do
				local trimmed
				trimmed=$(trim_value "$item")
				if [ -n "$trimmed" ]; then
					echo "    - ${trimmed}"
				fi
			done
		fi
	} >> "$config_path"
}

apply_mixin_config() {
	local config_path="$1"
	local base_dir="${2:-$Server_Dir}"
	local mixin_dir="${CLASH_MIXIN_DIR:-$base_dir/conf/mixin.d}"
	local mixin_paths=()

	if [ -n "${CLASH_MIXIN_PATHS:-}" ]; then
		IFS=',' read -r -a mixin_paths <<< "$CLASH_MIXIN_PATHS"
	fi

	if [ -d "$mixin_dir" ]; then
		while IFS= read -r -d '' file; do
			mixin_paths+=("$file")
		done < <(find "$mixin_dir" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 | sort -z)
	fi

	for path in "${mixin_paths[@]}"; do
		local trimmed
		trimmed=$(trim_value "$path")
		if [ -z "$trimmed" ]; then
			continue
		fi
		if [ "${trimmed:0:1}" != "/" ]; then
			trimmed="$base_dir/$trimmed"
		fi
		if [ -f "$trimmed" ]; then
			{
				echo ""
				echo "# ---- mixin: ${trimmed} ----"
				cat "$trimmed"
			} >> "$config_path"
		else
			echo "[WARN] Mixin file not found: $trimmed" >&2
		fi
	done
}
