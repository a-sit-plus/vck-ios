import co.touchlab.skie.configuration.DefaultArgumentInterop
import co.touchlab.skie.configuration.EnumInterop
import co.touchlab.skie.configuration.SealedInterop
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework

plugins {
    alias(libs.plugins.kotlinMultiplatform)
    id("co.touchlab.skie") version "0.10.14"
}

group = "at.asitplus.wallet"
version = "1.0.1"



val xcframeworkName = "vck-ios"
val xcf = XCFramework(xcframeworkName)


val walletDependencies= listOf(
    libs.vck,

    libs.vck.data.dif,
    libs.vck.data.openid,
    libs.vck.data.csc,
    libs.vck.openid,
    libs.vck.openid.ktor,
    //extend with new VC-K 7 modules, once VC-K 7 lands

    //credentials: gone with VC-K 7
    libs.credential.mdl,
    libs.credential.eupid.sdjwt,

    libs.signum.indispensable,
    libs.signum.indispensable.josef,
    libs.signum.indispensable.cosef,
    libs.signum.supreme,

    libs.kmmresult,
    libs.napier,
)

kotlin {

    listOf(
    iosArm64(),
    iosSimulatorArm64(),
    ).forEach { iosTarget ->
        iosTarget.binaries.framework {
            baseName = xcframeworkName
            binaryOption("bundleId", "at.asitplus.wallet.$xcframeworkName")
            isStatic = true
            xcf.add(this)
            walletDependencies.forEach {export(it)}
        }
    }
    sourceSets {
        commonMain.dependencies {
            walletDependencies.forEach {api(it)}
        }

        commonTest.dependencies {
            implementation(libs.kotlin.test)
        }
    }
}

skie {
    features {
        defaultArgumentsInExternalLibraries.set(true)

        group {
            SealedInterop.ExportEntireHierarchy(true) // or false
        }

        group("at.asitplus.signum.indispensable.HMAC") {
            EnumInterop.Enabled(false)
        }

        group("at.asitplus.dcapi") {
            DefaultArgumentInterop.Enabled(true)
        }

        group("at.asitplus.wallet") {
            DefaultArgumentInterop.Enabled(true)
        }

        group("at.asitplus.iso") {
            DefaultArgumentInterop.Enabled(true)
        }
    }
}
