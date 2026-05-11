import org.jetbrains.kotlin.gradle.dsl.JvmTarget

import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework

plugins {
    alias(libs.plugins.kotlinMultiplatform)
}

group = "at.asitplus.wallet"
version = "1.0.0"



val xcframeworkName = "vck-ios"
val xcf = XCFramework(xcframeworkName)


val walletDependencies= listOf(
    libs.vck,
    libs.vck.openid,
    libs.vck.openid.ktor,
    libs.credential.mdl,
    libs.credential.eupid.sdjwt,
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